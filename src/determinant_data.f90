module determinant_data

! Generation, inspection and manipulation of Slater determinants.

use const

implicit none

! --- FCIQMC info ---

! A handy type for containing a lot of information about a determinant.
! This is convenient for passing around different amounts of info when
! we need consistent interfaces.
! Not all compenents are necessarily allocated: only those needed at the time.
type det_info_t
    ! bit representation of determinant.
    integer(i0), pointer :: f(:)  => NULL()  ! (tot_string_len)
    integer(i0), pointer :: f2(:)  => NULL()  ! (tot_string_len); for DMQMC
    ! List of occupied spin-orbitals.
    integer, pointer :: occ_list(:)  => NULL()  ! (nel)
    ! List of unoccupied spin-orbitals
    integer, pointer :: unocc_list(:) ! (nvirt)
    ! List of occupied alpha/beta spin-orbitals
    integer, pointer :: occ_list_alpha(:), occ_list_beta(:) !(nel) WARNING: don't assume otherwise.
    ! List of unoccupied alpha/beta spin-orbitals
    integer, pointer :: unocc_list_alpha(:), unocc_list_beta(:)
    ! Number of unoccupied orbitals with each spin and symmetry.
    ! The first index maps to spin using (Ms+3)/2, where Ms=-1 is spin-down and
    ! Ms=1 is spin-up.
    integer, pointer :: symunocc(:,:) ! (2,sym0_tot:sym_max_tot)
    ! heat_bath weights to select i in a double excitation
    real(p), pointer :: i_d_weights_occ(:) ! (nel)
    real(p) :: i_d_weights_occ_tot
    ! heat bath weights to select i in a single excitation
    real(p), pointer :: i_s_weights_occ(:) ! (nel)
    real(p) :: i_s_weights_occ_tot
    ! heat bath weights to select a given i in a single excitation
    real(p), pointer :: ia_s_weights_occ(:,:) ! (virt, nel)
    ! position of different orbitals in this det compared to reference
    ! First column refers to orbitals in reference, second column to corresponding orbitals in det.
    integer, pointer :: diff_det_to_ref_orbs(:,:) ! (nel, 2)
    ! Number of orbitals that are different between det and reference.
    integer :: nex
    ! is the determinant an initiator determinant or not? (used only in
    ! i-FCIQMC). The i-th bit is set if the determinant is not an initiator in
    ! space i.
    integer :: initiator_flag
    ! \sum_i F_i - F_0, where F_i is the single-particle eigenvalue of the i-th occupied orbital 
    ! and F_0 is the corresponding sum for the reference determinant.
    ! Initialize this as a signalling nan just in case
    real(p) :: fock_sum = huge(1.0_p) 
    ! TODO when appropriate more universal fortran support is available, use some sort of NaN above.

    ! Pointer (never allocated) to corresponding elements in particle_t%dat array.
    real(p), pointer :: data(:) => NULL()
end type det_info_t

end module determinant_data
