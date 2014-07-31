module fciqmc

! Module for performing optimised (hopefully!) full configuration interaction
! quantum monte carlo (FCIQMC) calculations.

use fciqmc_data
use proc_pointers
implicit none

contains

    subroutine do_fciqmc(sys)

        ! Run the FCIQMC or initiator-FCIQMC algorithm starting from the initial walker
        ! distribution using the timestep algorithm.

        ! See notes about the implementation of this using function pointers
        ! in fciqmc_main.

        ! In:
        !    sys: system being studied.

        use parallel

        use annihilation, only: direct_annihilation
        use basis, only: basis_length, nbasis
        use calc, only: folded_spectrum, doing_calc, seed, initiator_approximation
        use determinants, only: det_info, alloc_det_info, dealloc_det_info
        use excitations, only: excit, create_excited_det
        use spawning, only: create_spawned_particle_initiator
        use qmc_common
        use ifciqmc, only: set_parent_flag
        use folded_spectrum_utils, only: cdet_excit
        use dSFMT_interface, only: dSFMT_t, dSFMT_init
        use utils, only: rng_init_info
        use semi_stoch, only: semi_stoch_t, check_if_determ, determ_projection
        use semi_stoch, only: empty_determ_space, dealloc_semi_stoch_t, init_semi_stoch_t
        use system, only: sys_t
        use restart_hdf5, only: restart_info_global, dump_restart_hdf5

        type(sys_t), intent(in) :: sys

        type(det_info) :: cdet
        type(dSFMT_t) :: rng
        type(semi_stoch_t) :: determ

        integer :: idet, ireport, icycle, iparticle, ideterm
        integer(lint) :: nattempts
        real(dp) :: nparticles_old(sampling_size)

        integer(i0) :: f_child(basis_length)
        integer(int_p) :: nspawned, ndeath
        integer :: nattempts_current_det
        type(excit) :: connection
        real(p) :: hmatel
        real(dp) :: real_population

        logical :: soft_exit
        logical :: semi_stochastic, determ_parent, determ_child

        real :: t1

        if (parent) call rng_init_info(seed+iproc)
        call dSFMT_init(seed+iproc, 50000, rng)

        ! Allocate det_info components.
        call alloc_det_info(sys, cdet, .false.)
        ! Folded spectrum *needs* the bit strings to be allocated as it needs
        ! be able to manipulate the bit string to create excited states.
        if (doing_calc(folded_spectrum)) call alloc_det_info(sys, cdet_excit)

        call init_semi_stoch_t(determ, sys, qmc_spawn, determ_space_type, determ_target_size)

        ! from restart
        nparticles_old = tot_nparticles

        ! Are we using a non-empty semi-stochastic space?
        semi_stochastic = .not. (determ%space_type == empty_determ_space)

        ! Main fciqmc loop.
        if (parent) call write_fciqmc_report_header()
        call initial_fciqmc_status(sys)
        ! Initialise timer.
        call cpu_time(t1)

        do ireport = 1, nreport

            ! Zero report cycle quantities.
            call init_report_loop()

            do icycle = 1, ncycles

                call init_mc_cycle(nattempts, ndeath)
                ideterm = 0

                do idet = 1, tot_walkers ! loop over walkers/dets

                    cdet%f => walker_dets(:,idet)
                    cdet%data => walker_data(:,idet)

                    call decoder_ptr(sys, cdet%f, cdet)

                    ! Extract the real sign from the encoded sign.
                    real_population = real(walker_population(1,idet),dp)/real_factor

                    ! If this is a deterministic state then copy its population
                    ! across to the determ%vector array.
                    if (determ%flags(idet) == 0) then
                        ideterm = ideterm + 1
                        determ%vector(ideterm) = real_population
                        determ_parent = .true.
                    else
                        determ_parent = .false.
                    end if

                    ! It is much easier to evaluate the projected energy at the
                    ! start of the i-FCIQMC cycle than at the end, as we're
                    ! already looping over the determinants.
                    call update_proj_energy_ptr(sys, f0, cdet, real_population, D0_population_cycle, &
                                                proj_energy, connection, hmatel)

                    ! Is this determinant an initiator?
                    call set_parent_flag_ptr(real_population, cdet%f, determ%flags(idet), cdet%initiator_flag)

                    nattempts_current_det = decide_nattempts(rng, real_population)

                    do iparticle = 1, nattempts_current_det

                        ! Attempt to spawn.
                        call spawner_ptr(rng, sys, qmc_spawn%cutoff, real_factor, cdet, walker_population(1,idet), &
                                         gen_excit_ptr, nspawned, connection)

                        ! Spawn if attempt was successful.
                        if (nspawned /= 0_int_p) then
                            if (determ_parent) then
                                call create_excited_det(cdet%f, connection, f_child)
                                determ_child = check_if_determ(determ%hash_table, determ%dets, f_child)
                                ! If the spawning is both from and to the
                                ! deterministic space, cancel it.
                                if (.not. determ_child) then
                                    call create_spawned_particle_ptr(cdet, connection, nspawned, 1, qmc_spawn, f_child)
                                end if
                            else
                                call create_spawned_particle_ptr(cdet, connection, nspawned, 1, qmc_spawn)
                            end if

                        end if

                    end do

                    ! Clone or die.
                    if (.not. determ_parent) call death_ptr(rng, walker_data(1,idet), shift(1), &
                                                            walker_population(1,idet), nparticles(1), ndeath)

                end do

                if (semi_stochastic) call determ_projection(rng, qmc_spawn, determ)

                call direct_annihilation(sys, rng, initiator_approximation, determ%flags)

                call end_mc_cycle(ndeath, nattempts)

            end do

            call end_report_loop(ireport, nparticles_old, t1, soft_exit)

            if (soft_exit) exit

        end do

        if (parent) then
            call write_fciqmc_final(ireport)
            write (6,'()')
        end if

        call load_balancing_report()

        if (soft_exit) then
            mc_cycles_done = mc_cycles_done + ncycles*ireport
        else
            mc_cycles_done = mc_cycles_done + ncycles*nreport
        end if

        if (dump_restart_file) then
            call dump_restart_hdf5(restart_info_global, mc_cycles_done, nparticles_old)
            if (parent) write (6,'()')
        end if

        call dealloc_semi_stoch_t(determ)

        call dealloc_det_info(cdet, .false.)
        if (doing_calc(folded_spectrum)) call dealloc_det_info(cdet_excit)

    end subroutine do_fciqmc

end module fciqmc
