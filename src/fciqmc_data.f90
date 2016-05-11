module fciqmc_data

! Data for fciqmc calculations and procedures which manipulate fciqmc and only
! fciqmc data.

use const
use csr, only: csrp_t
use spawn_data, only: spawn_t
use hash_table, only: hash_table_t
use parallel, only: parallel_timing_t

implicit none

contains

    !--- Statistics. ---

    function spawning_rate(nspawn_events, ndeath, real_factor, nattempts) result(rate)

        ! Calculate the rate of spawning on the current processor.
        ! In:
        !    nspawn_events: number of successful spawning events during the
        !       MC cycle.
        !    ndeath: (unscaled) number of particles that were killed/cloned
        !       during the MC cycle.
        !    real_factor: The factor by which populations are multiplied to
        !        enable non-integer populations.
        !    nattempts: The number of attempts to spawn made in order to
        !       generate the current population of walkers in the spawned arrays.

        real(p) :: rate
        integer, intent(in) :: nspawn_events
        integer(int_p), intent(in) :: ndeath, real_factor
        integer(int_64), intent(in) :: nattempts
        real(p) :: ndeath_real

        ! Death is not scaled when using reals.
        ndeath_real = real(ndeath,p)/real_factor

        ! The total spawning rate is
        !   (nspawn + ndeath) / nattempts
        ! In, for example, the timestep algorithm each particle has 2 attempts
        ! (one to spawn on a different determinant and one to clone/die).
        ! ndeath is the number of particles that died, which hence equals the
        ! number of successful death attempts (assuming the timestep is not so
        ! large that death creates more than one particle).
        ! By ignoring the number of particles spawned in a single event, we
        ! hence are treating the death and spawning events on the same footing.
        if (nattempts > 0) then
            rate = (nspawn_events + ndeath_real)/nattempts
        else
            ! Can't have done anything.
            rate = 0.0_p
        end if

    end function spawning_rate

    !--- Output procedures ---

    subroutine write_fciqmc_report_header(ntypes, dmqmc_in, max_excit)

        ! In:
        !    ntypes: number of particle types being sampled.
        ! In (optional):
        !    dmqmc_in: input options relating to DMQMC.
        !    max_excit: The maximum number of excitations for the system.

        use calc, only: doing_calc, hfs_fciqmc_calc, dmqmc_calc, doing_dmqmc_calc
        use calc, only: dmqmc_energy, dmqmc_energy_squared, dmqmc_staggered_magnetisation
        use calc, only: dmqmc_correlation, dmqmc_full_r2, dmqmc_rdm_r2, dmqmc_kinetic_energy
        use calc, only: dmqmc_H0_energy, dmqmc_potential_energy, dmqmc_HI_energy
        use dmqmc_data, only: dmqmc_in_t
        use utils, only: int_fmt

        integer, intent(in) :: ntypes
        type(dmqmc_in_t), optional, intent(in) :: dmqmc_in
        integer, optional, intent(in) :: max_excit

        integer :: i, j
        character(16) :: excit_header

        ! Data table info.
        write (6,'(1X,"Information printed out every QMC report loop:",/)')
        write (6,'(1X,"Shift: the energy offset calculated at the end of the report loop.")')
        if (.not. doing_calc(dmqmc_calc)) then
            write (6,'(1X,"H_0j: <D_0|H|D_j>, Hamiltonian matrix element.")')
            write (6,'(1X,"N_j: population of Hamiltonian particles on determinant D_j.")')
            if (doing_calc(hfs_fciqmc_calc)) then
                write (6,'(1X,"O_0j: <D_0|O|D_j>, operator matrix element.")')
                write (6,'(1X,a67)') "N'_j: population of Hellmann--Feynman particles on determinant D_j."
                write (6,'(1X,"# HF psips: current total population of Hellmann--Feynman particles.")')
            end if
        else
            if (doing_dmqmc_calc(dmqmc_full_r2)) then
                write (6, '(1X,a104)') 'Trace: The current total population on the diagonal elements of the &
                                     &first replica of the density matrix.'
                write (6, '(1X,a107)') 'Trace 2: The current total population on the diagonal elements of the &
                                     &second replica of the density matrix.'
            else
                write (6, '(1X,a83)') 'Trace: The current total population on the diagonal elements of the &
                                     &density matrix.'
            end if
            if (doing_dmqmc_calc(dmqmc_full_r2)) then
                write (6, '(1X,a81)') 'Full S2: The numerator of the estimator for the Renyi entropy of the &
                                      &full system.'
            end if
            if (doing_dmqmc_calc(dmqmc_energy)) then
                write (6, '(1X,a92)') '\sum\rho_{ij}H_{ji}: The numerator of the estimator for the expectation &
                                     &value of the energy.'
            end if
            if (doing_dmqmc_calc(dmqmc_energy_squared)) then
                write (6, '(1X,a100)') '\sum\rho_{ij}H2{ji}: The numerator of the estimator for the expectation &
                                     &value of the energy squared.'
            end if
            if (doing_dmqmc_calc(dmqmc_correlation)) then
                write (6, '(1X,a111)') '\sum\rho_{ij}S_{ji}: The numerator of the estimator for the expectation &
                                     &value of the spin correlation function.'
            end if
            if (doing_dmqmc_calc(dmqmc_staggered_magnetisation)) then
                write (6, '(1X,a109)') '\sum\rho_{ij}M2{ji}: The numerator of the estimator for the expectation &
                                     &value of the staggered magnetisation.'
            end if
            if (doing_dmqmc_calc(dmqmc_rdm_r2)) then
                write (6, '(1x,a73)') 'RDM(n) S2: The numerator of the estimator for the Renyi entropy of RDM n.'
            end if
            if (dmqmc_in%rdm%calc_inst_rdm) then
                write (6, '(1x,a83)') 'RDM(n) trace m: The current total population on the diagonal of replica m &
                                      &of RDM n.'
            end if
            if (present(dmqmc_in)) then
                if (dmqmc_in%calc_excit_dist) write (6, '(1x,a86)') &
                    'Excit. level n: The fraction of particles on excitation level n of the density matrix.'
            end if
        end if

        write (6,'(1X,"# H psips: current total population of Hamiltonian particles.")')
        write (6,'(1X,"# states: number of many-particle states occupied.")')
        write (6,'(1X,"# spawn_events: number of successful spawning events across all processors.")')
        write (6,'(1X,"R_spawn: average rate of spawning across all processors.")')
        write (6,'(1X,"time: average time per Monte Carlo cycle.",/)')
        write (6,'(1X,"Note that all particle populations are averaged over the report loop.",/)')

        ! Header of data table.
        if (doing_calc(dmqmc_calc)) then
           write (6,'(1X,a12,3X,a13,17X,a5)', advance = 'no') &
           '# iterations','Instant shift','Trace'

            if (doing_dmqmc_calc(dmqmc_full_r2)) then
                write (6, '(13X,a7,14X,a7)', advance = 'no') 'Trace 2','Full S2'
            end if
            if (doing_dmqmc_calc(dmqmc_energy)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}H_{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_energy_squared)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}H2{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_correlation)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}S_{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_staggered_magnetisation)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}M2{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_kinetic_energy)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}T_{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_H0_energy)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}H0{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_HI_energy)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}HI{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_potential_energy)) then
                write (6, '(2X,a19)', advance = 'no') '\sum\rho_{ij}U_{ji}'
            end if
            if (doing_dmqmc_calc(dmqmc_rdm_r2)) then
                do i = 1, dmqmc_in%rdm%nrdms
                    write (6, '(16X,a3,'//int_fmt(i,0)//',1x,a2)', advance = 'no') 'RDM', i, 'S2'
                end do
            end if
            if (dmqmc_in%rdm%calc_inst_rdm) then
                do i = 1, dmqmc_in%rdm%nrdms
                    do j = 1, ntypes
                        write (6, '(7X,a3,'//int_fmt(i,0)//',1x,a5,1x,'//int_fmt(j,0)//')', advance = 'no') &
                                'RDM', i, 'trace', j
                    end do
                end do
            end if
            if (present(dmqmc_in)) then
                if (dmqmc_in%calc_excit_dist) then
                    do i = 0, max_excit
                        write (excit_header, '("Excit. level",1X,'//int_fmt(i,0)//')') i
                        write (6, '(5X,a16)', advance='no') excit_header
                    end do
                end if
            end if

            write (6, '(3X,a11,6X)', advance='no') '# particles'

        else
            write (6,'(1X,a13,3(2X,a17))', advance='no') &
                     "# iterations ", "Shift            ", "\sum H_0j N_j    ", "N_0              "
            if (doing_calc(hfs_fciqmc_calc)) then
                write (6,'(6(2X,a17))', advance='no') &
                    "H.F. Shift       ","\sum O_0j N_j    ","\sum H_0j N'_j   ","N'_0             ", &
                    "# H psips        ","# HF psips       "
            else
                write (6,'(4X,a9,8X)', advance='no') "# H psips"
            end if
        end if
        write (6,'(3X,"# states  # spawn_events  R_spawn   time")')

    end subroutine write_fciqmc_report_header

    subroutine write_fciqmc_report(qmc_in, qs, ireport, ntot_particles, elapsed_time, comment, non_blocking_comm, &
                                   dmqmc_in, dmqmc_estimates)

        ! Write the report line at the end of a report loop.

        ! In:
        !    qmc_in: input options relating to QMC methods.
        !    qs: QMC state (containing shift and various estimators).
        !    ireport: index of the report loop.
        !    ntot_particles: total number of particles in main walker list.
        !    elapsed_time: time taken for the report loop.
        !    comment: if true, then prefix the line with a #.
        !    non_blocking_comm: true if using non-blocking communications
        ! In (optional):
        !    dmqmc_in: input options relating to DMQMC.
        !    dmqmc_estimates: type containing all DMQMC estimates to be printed.

        use calc, only: doing_calc, dmqmc_calc, hfs_fciqmc_calc, doing_dmqmc_calc
        use calc, only: dmqmc_energy, dmqmc_energy_squared, dmqmc_full_r2, dmqmc_rdm_r2
        use calc, only: dmqmc_correlation, dmqmc_staggered_magnetisation, dmqmc_kinetic_energy
        use calc, only: dmqmc_H0_energy, dmqmc_potential_energy, dmqmc_HI_energy
        use dmqmc_data, only: dmqmc_in_t, dmqmc_estimates_t, energy_ind, energy_squared_ind
        use dmqmc_data, only: correlation_fn_ind, staggered_mag_ind, full_r2_ind, kinetic_ind
        use dmqmc_data, only: H0_ind, potential_ind, HI_ind
        use qmc_data, only: qmc_in_t, qmc_state_t

        type(qmc_in_t), intent(in) :: qmc_in
        type(qmc_state_t), intent(in) :: qs
        integer, intent(in) :: ireport
        real(dp), intent(in) :: ntot_particles(:)
        real, intent(in) :: elapsed_time
        logical, intent(in) :: comment, non_blocking_comm
        type(dmqmc_in_t), optional, intent(in) :: dmqmc_in
        type(dmqmc_estimates_t), optional, intent(in) :: dmqmc_estimates

        integer :: mc_cycles, i, j, ntypes

        ntypes = size(ntot_particles)

        ! For non-blocking communications we print out the nth report loop
        ! after the (n+1)st iteration. Adjust mc_cycles accordingly
        if (.not. non_blocking_comm) then
            mc_cycles = ireport*qmc_in%ncycles
        else
            mc_cycles = (ireport-1)*qmc_in%ncycles
        end if

        if (comment) then
            write (6,'(1X,"#",1X)', advance='no')
        else
            write (6,'(3X)', advance='no')
        end if

        ! See also the format used in inital_fciqmc_status if this is changed.

        ! DMQMC output.
        if (doing_calc(dmqmc_calc)) then
            write (6,'(i10,2X,es17.10,2X,es17.10)',advance = 'no') &
                (qs%mc_cycles_done+mc_cycles-qmc_in%ncycles), qs%shift(1), dmqmc_estimates%trace(1)
            ! The trace on the second replica.
            if (doing_dmqmc_calc(dmqmc_full_r2)) then
                write(6, '(3X,es17.10)',advance = 'no') dmqmc_estimates%trace(2)
            end if

            ! Renyi-2 entropy for the full density matrix.
            if (doing_dmqmc_calc(dmqmc_full_r2)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(full_r2_ind)
            end if

            ! Energy.
            if (doing_dmqmc_calc(dmqmc_energy)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(energy_ind)
            end if

            ! Energy squared.
            if (doing_dmqmc_calc(dmqmc_energy_squared)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(energy_squared_ind)
            end if

            ! Correlation function.
            if (doing_dmqmc_calc(dmqmc_correlation)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(correlation_fn_ind)
            end if

            ! Staggered magnetisation.
            if (doing_dmqmc_calc(dmqmc_staggered_magnetisation)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(staggered_mag_ind)
            end if

            ! Kinetic energy
            if (doing_dmqmc_calc(dmqmc_kinetic_energy)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(kinetic_ind)
            end if

            ! H^0 energy, where H = H^0 + V.
            if (doing_dmqmc_calc(dmqmc_H0_energy)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(H0_ind)
            end if

            ! H^I energy, where H^I = exp(-(beta-tau)/2 H^0) H exp(-(beta-tau)/2. H^0).
            if (doing_dmqmc_calc(dmqmc_HI_energy)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(HI_ind)
            end if

            ! Potential energy.
            if (doing_dmqmc_calc(dmqmc_potential_energy)) then
                write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%numerators(potential_ind)
            end if

            ! Renyi-2 entropy for all RDMs being sampled.
            if (doing_dmqmc_calc(dmqmc_rdm_r2)) then
                do i = 1, dmqmc_in%rdm%nrdms
                    write (6, '(6X,es17.10)', advance = 'no') dmqmc_estimates%inst_rdm%renyi_2(i)
                end do
            end if

            ! Traces for instantaneous RDM estimates.
            if (dmqmc_in%rdm%calc_inst_rdm) then
                do i = 1, dmqmc_in%rdm%nrdms
                    do j = 1, ntypes
                        write (6, '(2x,es17.10)', advance = 'no') dmqmc_estimates%inst_rdm%traces(j,i)
                    end do
                end do
            end if

            ! The distribution of walkers on different excitation levels of the
            ! density matrix.
            if (present(dmqmc_in)) then
                if (dmqmc_in%calc_excit_dist) then
                    do i = 0, ubound(dmqmc_estimates%excit_dist,1)
                        write (6, '(4X,es17.10)', advance = 'no') dmqmc_estimates%excit_dist(i)/ntot_particles(1)
                    end do
                end if
            end if

            write (6, '(2X,es17.10)', advance='no') ntot_particles(1)

        else if (doing_calc(hfs_fciqmc_calc)) then
            write (6,'(i10,2X,6(es17.10,2X),es17.10,4X,es17.10,1X,es17.10)', advance = 'no') &
                                             qs%mc_cycles_done+mc_cycles, qs%shift(1),   &
                                             qs%estimators%proj_energy, qs%estimators%D0_population, &
                                             qs%shift(2), qs%estimators%proj_hf_O_hpsip, qs%estimators%proj_hf_H_hfpsip, &
                                             qs%estimators%D0_hf_population, &
                                             ntot_particles
        else
            write (6,'(i10,2X,2(es17.10,2X),es17.10,4X,es17.10)', advance='no') &
                                             qs%mc_cycles_done+mc_cycles, qs%shift(1),   &
                                             qs%estimators%proj_energy, qs%estimators%D0_population, &
                                             ntot_particles
        end if
        write (6,'(2X,i10,4X,i12,2X,f7.4,2X,f7.3)') qs%estimators%tot_nstates, qs%estimators%tot_nspawn_events, &
                                             qs%spawn_store%rspawn, elapsed_time/qmc_in%ncycles

    end subroutine write_fciqmc_report

    subroutine end_fciqmc(reference, psip_list, spawn)

        ! Deallocate fciqmc data arrays.

        ! In/Out (optional):
        !   reference: reference state. On exit, allocatable components are deallocated.
        !   psip_list: main particle_t object.  On exit, allocatable components are deallocated.
        !   spawn: spawn_t object.  On exit, allocatable components are deallocated.

        use checking, only: check_deallocate
        use spawn_data, only: dealloc_spawn_t
        use load_balancing, only: dealloc_parallel_t
        use qmc_data, only: particle_t
        use reference_determinant, only: reference_t, dealloc_reference_t

        type(reference_t), intent(inout), optional :: reference
        type(particle_t), intent(inout), optional :: psip_list
        type(spawn_t), intent(inout), optional :: spawn

        integer :: ierr

        if (present(reference)) then
            call dealloc_reference_t(reference)
        end if
        if (present(psip_list)) then
            if (allocated(psip_list%nparticles)) then
                deallocate(psip_list%nparticles, stat=ierr)
                call check_deallocate('psip_list%nparticles',ierr)
            end if
            if (allocated(psip_list%states)) then
                deallocate(psip_list%states, stat=ierr)
                call check_deallocate('psip_list%states',ierr)
            end if
            if (allocated(psip_list%pops)) then
                deallocate(psip_list%pops, stat=ierr)
                call check_deallocate('psip_list%pops',ierr)
            end if
            if (allocated(psip_list%dat)) then
                deallocate(psip_list%dat, stat=ierr)
                call check_deallocate('psip_list%dat',ierr)
            end if
            if (allocated(psip_list%nparticles_proc)) then
                deallocate(psip_list%nparticles_proc, stat=ierr)
                call check_deallocate('psip_list%nparticles_proc', ierr)
            end if
        end if
        if (present(spawn)) call dealloc_spawn_t(spawn)

    end subroutine end_fciqmc

end module fciqmc_data
