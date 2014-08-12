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

    subroutine neel_trial_state(sys, cdet, connection, hmatel)

        ! Apply the transformation to the Hamiltonian matrix element due to
        ! using the Neel singlet state as the trial function.

        ! In:
        !    sys: system being studied.
        !    cdet: info on the current determinant (cdet) that we will spawn
        !        from.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are spawned.
        ! In/Out:
        !    hmatel: on input, untransformed matrix element connecting two spin
        !        functions (kets).  On output, transformed matrix element,
        !        \Psi_i^T H_{ij} 1/\Psi_j^T.

        use determinants, only: det_info_t
        use excitations, only: excit
        use fciqmc_data, only: neel_singlet_amp, sampling_size
        use system, only: sys_t

        type(sys_t), intent(in) :: sys
        type(det_info_t), intent(in) :: cdet
        type(excit), intent(in) :: connection
        real(p), intent(inout) :: hmatel

        integer :: up_spins_to, up_spins_from
        integer :: bit_position, bit_element

        ! Find the number of up spins on sublattice 1.
        up_spins_from = nint(cdet%data(sampling_size+1))
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
        hmatel = (neel_singlet_amp(up_spins_to)*hmatel)/neel_singlet_amp(up_spins_from)

    end subroutine neel_trial_state

    subroutine dmqmc_weighting_fn(sys, cdet, connection, hmatel)

        ! Apply a transformation to the Hamiltonian matrix element by
        ! reducing the probability of spawning to higher excitation levels
        ! between the two ends of the DMQMC bitstring. The exact trial function
        ! used is specified by the users upon input, and stored in the vector
        ! dmqmc_accumulated_probs.

        ! In:
        !    sys: system being studied.
        !    cdet: info on the current determinant (cdet) that we will spawn
        !        from.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are spawned.
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
        use excitations, only: excit, get_excitation_level, create_excited_det
        use fciqmc_data, only: dmqmc_accumulated_probs
        use system, only: sys_t

        type(sys_t), intent(in) :: sys
        type(det_info_t), intent(in) :: cdet
        type(excit), intent(in) :: connection
        real(p), intent(inout) :: hmatel
        integer(i0) :: f_new(sys%basis%string_len)
        integer :: excit_level_old, excit_level_new

        excit_level_old = get_excitation_level(cdet%f,cdet%f2)

        call create_excited_det(sys%basis, cdet%f, connection, f_new)

        excit_level_new = get_excitation_level(f_new,cdet%f2)

        hmatel = dmqmc_accumulated_probs(excit_level_old)*hmatel*(1/dmqmc_accumulated_probs(excit_level_new))

    end subroutine dmqmc_weighting_fn

end module importance_sampling
