module importance_sampling

! Module for applying importance sampling transforms to the Hamiltonian, e.g. to
! stochastically sample \tilde{H}_{ij} = \psi^{(T})_i H_{ij} 1/\psi^{(T})_j
! rather than just H_{ij}.

! Instead of propogating using

! dc_i
! ---- = - \sum_j H_{ij} c_j
!  dt

! we instead propogate using

! df_i      \sum_j \psi^{(T)}_i H_{ij}      1        f_j
! ---- = -                             ------------
!  dt                                  \psi^{(T)}_j 

! where

! f_i = \psi^{(T)}_i c_i

! and \psi^{(T)}_i is the weight of the trial function on i.

! As we currently generate the excitations uniformly, this amounts to simply
! scaling H_{ij} appropriately after generating the excitation (as usual) but
! before testing whether or not to accept the spawning attempt (which depends
! upon the connecting Hamiltonian matrix element, which has changed).

! This module contains the appropriate functions required to transform the
! Hamiltonian matrix element according to the trial function being used.

! Note that the projected estimator must also be adjusted accordingly.

! In order to be accessible via a common function pointer, these subroutines
! should have the interface defined by i_trial_fn.

use const

implicit none

contains

    pure function importance_sampling_weight(guiding_function, cdet, pop) result(weight)

        ! Calculate c_i from f_i.

        ! In:
        !    guiding_function: guiding function in use.  See enum in qmc_data for possible options.
        !    cdet: det_info_t object representing the i-th state (tensor product, determinant, etc.).
        !    pop: current population on i, giving a stochastic representation of f_i.
        ! Returns:
        !    stochastic representation of c_i.

        use determinants, only: det_info_t
        use qmc_data, only: single_basis, neel_singlet_guiding

        use fciqmc_data, only: neel_singlet_amp

        real(p) :: weight
        integer, intent(in) :: guiding_function
        type(det_info_t), intent(in) :: cdet
        real(p), intent(in) :: pop
        integer :: n

        select case(guiding_function)
        case(single_basis)
            weight = pop
        case(neel_singlet_guiding)
            n = nint(cdet%data(size(cdet%data)-1))
            weight = pop/neel_singlet_amp(n)
        end select

    end function importance_sampling_weight

    subroutine neel_trial_state(sys, cdet, connection, trial_func, hmatel)

        ! Apply the transformation to the Hamiltonian matrix element due to
        ! using the Neel singlet state as the trial function.

        ! In:
        !    sys: system being studied.
        !    cdet: info on the current determinant (cdet) that we will spawn
        !        from.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are spawned.
        !    trial_func: importance sampling weights.
        ! In/Out:
        !    hmatel: on input, untransformed matrix element connecting two spin
        !        functions (kets).  On output, transformed matrix element,
        !        \Psi_i^T H_{ij} 1/\Psi_j^T.

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use system, only: sys_t

        type(sys_t), intent(in) :: sys
        type(det_info_t), intent(in) :: cdet
        type(excit_t), intent(in) :: connection
        real(p), allocatable, intent(in) :: trial_func(:)
        real(p), intent(inout) :: hmatel

        integer :: up_spins_to, up_spins_from
        integer :: bit_position, bit_element

        ! Find the number of up spins on sublattice 1.
        ! WARNING: we assume the number of up spins is the penultimate element in cdet%data.
        up_spins_from = nint(cdet%data(size(cdet%data)-1))
        ! For the spin up which was flipped to create the connected
        ! basis function, find whether this spin was on sublattice 1 or 2.
        ! If it was on sublattice 1, the basis function we go to has 1 less
        ! up spin on sublattice 1, else it will have one more spin up here.
        bit_position = sys%basis%bit_lookup(1,connection%from_orb(1))
        bit_element = sys%basis%bit_lookup(2,connection%from_orb(1))
        if (btest(sys%heisenberg%lattice_mask(bit_element), bit_position)) then
            up_spins_to = up_spins_from-1
        else
            up_spins_to = up_spins_from+1
        end if

        ! For a given number of spins up on sublattice 1, n, the corresponding
        ! ampltidue of this basis function in the trial function is stored as
        ! neel_singlet_amp(n), for this particular trial function. Hence we have:
        hmatel = (trial_func(up_spins_to)*hmatel)/trial_func(up_spins_from)

    end subroutine neel_trial_state

    subroutine dmqmc_weighting_fn(sys, cdet, connection, trial_func, hmatel)

        ! Apply a transformation to the Hamiltonian matrix element by
        ! reducing the probability of spawning to higher excitation levels
        ! between the two ends of the DMQMC bitstring. The exact trial function
        ! used is specified by the users upon input, and stored in the vector
        ! accumulated_probs.

        ! In:
        !    sys: system being studied.
        !    cdet: info on the current determinant (cdet) that we will spawn
        !        from.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are spawned.
        !    trial_func: importance sampling weights.
        ! In/Out:
        !    hmatel: on input, untransformed matrix element connecting two spin
        !        functions (kets).  On output, transformed matrix element,
        !        \Psi^T(cdet%f,cdet%f2) H_{ij} 1/\Psi(f_new,cdet%f2).
        !        The factors which the Hamiltonian are multiplied by depend
        !        on the level which we come from, and go to, and so depend on
        !        the two ends of the bitstring we spawn from, and the new
        !        bitstring we spawn onto. Note this is different to more conventional
        !        importance sampling.

        use determinants, only: det_info_t
        use excitations, only: excit_t, get_excitation_level, create_excited_det
        use system, only: sys_t

        type(sys_t), intent(in) :: sys
        type(det_info_t), intent(in) :: cdet
        type(excit_t), intent(in) :: connection
        real(p), allocatable, intent(in) :: trial_func(:)
        real(p), intent(inout) :: hmatel
        integer(i0) :: f_new(sys%basis%string_len)
        integer :: excit_level_old, excit_level_new

        excit_level_old = get_excitation_level(cdet%f,cdet%f2)

        call create_excited_det(sys%basis, cdet%f, connection, f_new)

        excit_level_new = get_excitation_level(f_new,cdet%f2)

        hmatel = trial_func(excit_level_old)*hmatel*(1/trial_func(excit_level_new))

    end subroutine dmqmc_weighting_fn

end module importance_sampling
