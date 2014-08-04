module proc_pointers

use const, only: i0, p, dp, lint, int_p
use determinants, only: det_info
use excitations, only: excit

implicit none

! Note that Intel compilers (at least 11.1) don't like having using a variable
! that's imported as a array size in abstract interfaces.

abstract interface
    pure subroutine i_decoder(sys,f,d)
        use system, only: sys_t
        import :: i0, det_info
        implicit none
        type(sys_t), intent(in) :: sys
        integer(i0), intent(in) :: f(sys%basis%basis_length)
        type(det_info), intent(inout) :: d
    end subroutine i_decoder
    pure subroutine i_update_proj_energy(sys, f0, d, pop, D0_pop_sum, proj_energy_sum, excitation, hmatel)
        use system, only: sys_t
        import :: det_info, p, i0, excit
        implicit none
        type(sys_t), intent(in) :: sys
        integer(i0), intent(in) :: f0(:)
        type(det_info), intent(in) :: d
        real(p), intent(in) :: pop
        real(p), intent(inout) :: D0_pop_sum, proj_energy_sum
        type(excit), intent(out) :: excitation
        real(p), intent(out) :: hmatel
    end subroutine i_update_proj_energy
    subroutine i_update_proj_hfs(sys, f, fpop, f_hfpop, fdata, excitation, hmatel,&
                                     D0_hf_pop,proj_hf_O_hpsip, proj_hf_H_hfpsip)
        use system, only: sys_t
        import :: i0, p, excit
        implicit none
        type(sys_t), intent(in) :: sys
        integer(i0), intent(in) :: f(:)
        integer, intent(in) :: fpop, f_hfpop
        real(p), intent(in) :: fdata(:), hmatel
        type(excit), intent(in) :: excitation
        real(p), intent(inout) :: D0_hf_pop, proj_hf_O_hpsip, proj_hf_H_hfpsip
    end subroutine i_update_proj_hfs
    subroutine i_update_dmqmc_estimators(sys, idet,excitation,walker_pop)
        use system, only: sys_t
        import :: excit, p
        implicit none
        type(sys_t), intent(in) :: sys
        integer, intent(in) :: idet
        type(excit), intent(in) :: excitation
        real(p), intent(in) :: walker_pop
    end subroutine i_update_dmqmc_estimators
    subroutine i_gen_excit(rng, sys, d, pgen, connection, hmatel)
        use dSFMT_interface, only: dSFMT_t
        use system, only: sys_t
        import :: det_info, excit, p
        implicit none
        type(dSFMT_t), intent(inout) :: rng
        type(sys_t), intent(in) :: sys
        type(det_info), intent(in) :: d
        real(p), intent(out) :: pgen, hmatel
        type(excit), intent(out) :: connection
    end subroutine i_gen_excit
    subroutine i_gen_excit_finalise(rng, sys, d, connection, hmatel)
        use dSFMT_interface, only: dSFMT_t
        use system, only: sys_t
        import :: det_info, excit, p
        implicit none
        type(dSFMT_t), intent(inout) :: rng
        type(sys_t), intent(in) :: sys
        type(det_info), intent(in) :: d
        type(excit), intent(inout) :: connection
        real(p), intent(out) :: hmatel
    end subroutine i_gen_excit_finalise
    subroutine i_death(rng, mat, loc_shift, pop, tot_pop, ndeath)
        use dSFMT_interface, only: dSFMT_t
        import :: p, dp, int_p
        implicit none
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(in) :: mat
        real(p), intent(in) :: loc_shift
        integer(int_p), intent(inout) :: pop, ndeath
        real(dp), intent(inout) :: tot_pop
    end subroutine i_death
    pure function i_sc0(sys, f) result(hmatel)
        use system, only: sys_t
        import :: p, i0
        implicit none
        real(p) :: hmatel
        type(sys_t), intent(in) :: sys
        integer(i0), intent(in) :: f(sys%basis%basis_length)
    end function i_sc0
    subroutine i_set_parent_flag(pop, f, determ_flag, flag)
        import :: i0, p
        implicit none
        real(p), intent(in) :: pop
        integer(i0), intent(in) :: f(:)
        integer, intent(in) :: determ_flag
        integer, intent(out) :: flag
    end subroutine i_set_parent_flag
    subroutine i_create_spawned_particle(basis, d, connection, nspawned, particle_indx, spawn, f)
        use basis_types, only: basis_t
        use spawn_data, only: spawn_t
        import :: excit, det_info, int_p, i0
        implicit none
        type(basis_t), intent(in) :: basis
        type(det_info), intent(in) :: d
        type(excit), intent(in) :: connection
        integer(int_p), intent(in) :: nspawned
        integer, intent(in) :: particle_indx
        integer(i0), intent(in), optional, target :: f(:)
        type(spawn_t), intent(inout) :: spawn
    end subroutine i_create_spawned_particle
    subroutine i_create_spawned_particle_dm(basis, f1, f2, connection, nspawned, spawning_end, particle_indx, spawn)
        use spawn_data, only: spawn_t
        use basis_types, only: basis_t
        import :: excit, i0, int_p
        implicit none
        type(basis_t), intent(in) :: basis
        integer(i0), intent(in) :: f1(basis%basis_length)
        integer(i0), intent(in) :: f2(basis%basis_length)
        type(excit), intent(in) :: connection
        integer(int_p), intent(in) :: nspawned
        integer, intent(in) :: spawning_end, particle_indx
        type(spawn_t), intent(inout) :: spawn
    end subroutine i_create_spawned_particle_dm
    subroutine i_trial_fn(sys, cdet, connection, hmatel)
        use system, only: sys_t
        import :: det_info, excit, p
        type(sys_t), intent(in) :: sys
        type(det_info), intent(in) :: cdet
        type(excit), intent(in) :: connection
        real(p), intent(inout) :: hmatel
    end subroutine i_trial_fn

    ! generic procedures...
    subroutine i_sub()
    end subroutine i_sub

end interface

procedure(i_decoder), pointer :: decoder_ptr => null()

procedure(i_update_proj_energy), pointer :: update_proj_energy_ptr => null()
procedure(i_update_proj_hfs), pointer :: update_proj_hfs_ptr => null()

procedure(i_update_dmqmc_estimators), pointer :: update_dmqmc_energy_ptr => null()
procedure(i_update_dmqmc_estimators), pointer :: update_dmqmc_energy_squared_ptr => null()
procedure(i_update_dmqmc_estimators), pointer :: update_dmqmc_stag_mag_ptr => null()
procedure(i_update_dmqmc_estimators), pointer :: update_dmqmc_correlation_ptr => null()

procedure(i_death), pointer :: death_ptr => null()

procedure(i_sc0), pointer :: sc0_ptr => null()
procedure(i_sc0), pointer :: op0_ptr => null()

procedure(i_sub), pointer :: dmqmc_initial_distribution_ptr => null()

procedure(i_set_parent_flag), pointer :: set_parent_flag_ptr => null()

procedure(i_create_spawned_particle), pointer :: create_spawned_particle_ptr => null()
procedure(i_create_spawned_particle_dm), pointer :: create_spawned_particle_dm_ptr => null()


! Single structure for all types of excitation generator so we can use the same
! interface for spawning routines which use different types of generator.
type gen_excit_ptr_t
    procedure(i_gen_excit), nopass, pointer :: full => null()
    procedure(i_gen_excit), nopass, pointer :: init => null()
    procedure(i_gen_excit_finalise), nopass, pointer :: finalise => null()
    procedure(i_trial_fn), nopass, pointer :: trial_fn => null()
end type gen_excit_ptr_t

type(gen_excit_ptr_t) :: gen_excit_ptr, gen_excit_hfs_ptr

abstract interface
    subroutine i_spawner(rng, sys, spawn_cutoff, real_factor, d, parent_sign, gen_excit_ptr, nspawned, connection)
        use dSFMT_interface, only: dSFMT_t
        use system, only: sys_t
        import :: det_info, excit, gen_excit_ptr_t, int_p
        implicit none
        type(dSFMT_t), intent(inout) :: rng
        type(sys_t), intent(in) :: sys
        integer(int_p), intent(in) :: spawn_cutoff
        integer(int_p), intent(in) :: real_factor
        type(det_info), intent(in) :: d
        integer(int_p), intent(in) :: parent_sign
        type(gen_excit_ptr_t), intent(in) :: gen_excit_ptr
        integer(int_p), intent(out) :: nspawned
        type(excit), intent(out) :: connection
    end subroutine i_spawner
end interface

procedure(i_spawner), pointer :: spawner_ptr => null()
procedure(i_spawner), pointer :: spawner_hfs_ptr => null()

end module proc_pointers
