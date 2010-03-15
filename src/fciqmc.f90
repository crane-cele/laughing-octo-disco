module fciqmc

use fciqmc_data
implicit none

contains

    subroutine init_fciqmc()

        ! Initialisation for fciqmc calculations.
        ! Setup the spin polarisation for the system, initialise the RNG,
        ! allocate the required memory for the list of walkers and set the
        ! initial walker.

        use errors, only: stop_all
        use parallel, only: nprocs
        use utils, only: int_fmt

        use basis, only: basis_length
        use calc, only: sym_in, ms_in
        use determinants, only: encode_det, set_spin_polarisation, write_det
        use hamiltonian, only: get_hmatel_k, slater_condon0_hub_k
        use system, only: nel, nalpha, nbeta

        integer :: ierr
        integer :: i, occ_list(nel)

        if (nprocs > 1) call stop_all('init_fciqmc','Not (yet!) a parallel algorithm.')

        write (6,'(1X,a6,/,1X,6("-"),/)') 'FCIQMC'

        ! Allocate main walker lists.
        allocate(walker_dets(basis_length,walker_length), stat=ierr)
        allocate(walker_population(walker_length), stat=ierr)
        allocate(walker_energies(walker_length), stat=ierr)

        ! Allocate spawned walker lists.
        allocate(spawned_walker_dets(basis_length,spawned_walker_length), stat=ierr)
        allocate(spawned_walker_population(spawned_walker_length), stat=ierr)

        ! Set spin variables.
        call set_spin_polarisation(ms_in)

        ! Set initial walker population.
        tot_walkers = 1
        walker_population(tot_walkers) = 10

        ! Set the reference determinant to be the spin-orbitals with the lowest
        ! kinetic energy which satisfy the spin polarisation.
        ! Note: this is for testing only!  The symmetry input is currently
        ! ignored.
        forall (i=1:nalpha) occ_list(i) = 2*i-1
        forall (i=1:nbeta) occ_list(i+nalpha) = 2*i

        walker_dets(:,tot_walkers) = encode_det(occ_list)

        walker_energies(tot_walkers) = 0.0_dp

        ! Energy of reference determinant.
        H00 = slater_condon0_hub_k(occ_list)
        ! Reference det
        allocate(f0(basis_length), stat=ierr)
        f0 = walker_dets(:,tot_walkers)

        write (6,'(1X,a29,1X)',advance='no') 'Reference determinant, |D0> ='
        call write_det(walker_dets(:,tot_walkers), new_line=.true.)
        write (6,'(1X,a16,f20.12)') 'E0 = <D0|H|D0> =',H00
        write (6,'(/,1X,a68,/)') 'Note that FCIQMC calculates the correlation energy relative to |D0>.'
        
    end subroutine init_fciqmc

    subroutine do_fciqmc()

        ! Run the FCIQMC algorithm starting from the initial walker
        ! distribution.

        use annihilation, only: direct_annihilation
        use basis, only: basis_length
        use death, only: stochastic_death
        use determinants, only: det_info, decode_det_spinocc_spinunocc
        use projected_energy, only: update_proj_energy_hub_k
        use spawning, only: spawn_hub_k
        use system, only: nel, nalpha, nbeta, nvirt_alpha, nvirt_beta
        use simple_fciqmc, only: update_shift

        integer :: ierr
        integer :: idet, ireport, icycle, iparticle, nparticles, nparticles_old
        type(det_info) :: cdet

        ! Allocate det_info components.
        allocate(cdet%f(basis_length), stat=ierr)
        allocate(cdet%occ_list(nel), stat=ierr)
        allocate(cdet%occ_list_alpha(nalpha), stat=ierr)
        allocate(cdet%occ_list_beta(nbeta), stat=ierr)
        allocate(cdet%unocc_list_alpha(nvirt_alpha), stat=ierr)
        allocate(cdet%unocc_list_beta(nvirt_beta), stat=ierr)

        ! Main fciqmc loop.

        call write_fciqmc_report_header()

        do ireport = 1, nreport

            do icycle = 1, ncycles

                ! Reset the current position in the spawning array to be the
                ! slot preceding the first slot.
                spawning_head = 0

                ! Zero instantaneous projected energy.
                proj_energy = 0.0_dp

                do idet = 1, tot_walkers ! loop over walkers/dets

                    cdet%f = walker_dets(:,idet)

                    call decode_det_spinocc_spinunocc(cdet%f, cdet)

                    ! It is much easier to evaluate the projected energy at the
                    ! start of the FCIQMC cycle than at the end.
                    call update_proj_energy_hub_k(idet)

                    do iparticle = 1, abs(walker_population(idet))
                        
                        ! spawn
                        call spawn_hub_k(cdet, walker_population(idet))

                    end do

                    ! Clone or die.
                    call stochastic_death(idet)

                end do

                call direct_annihilation()

            end do

            ! Update the shift
            nparticles = sum(abs(walker_population(:tot_walkers))) ! This can be done more efficiently by counting as we go...
            if (vary_shift) then
                call update_shift(nparticles_old, nparticles, ncycles)
            end if
            nparticles_old = nparticles
            if (nparticles > target_particles) then
                vary_shift = .true.
            end if

            ! Normalise projected energy
            proj_energy = proj_energy/D0_population

            call write_fciqmc_report(ireport, nparticles)

        end do

        call write_fciqmc_final()

    end subroutine do_fciqmc

end module fciqmc
