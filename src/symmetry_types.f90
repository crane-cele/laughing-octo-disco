module symmetry_types

! Derived types for symmetry information

use const

implicit none

! Derived type for handling point group symmetry, as read in from FCIDUMP files.

! See discussion in point_group_symmetry.

type pg_sym_t
    ! The totally symmetric representation is given by the null bit string (with some Lz
    ! symmetry which is added later)
    integer :: gamma_sym = 0

    ! The following arrays are used to store information about number of basis functions
    ! of a given symmetry.  With Lz symmetry (which is not closed), the symmetries which can 
    ! be generated by products of basis fns (sym indices sym0_tot:sym_max_tot)are more than
    ! the basis functions themselves (sym0:sym_max).
    ! For speed within the excitation generators, it was decided to have these arrays over 
    ! the whole symmetry range to avoid a test for validity, though they are zero outside
    ! the sym0:sym_max range.
    ! 
    ! nbasis_sym(i) gives the number of (spin) basis functions in the i-th symmetry,
    ! where i is the bit string describing the irreducible representation.
    integer, allocatable :: nbasis_sym(:) ! (sym0_tot:sym_max_tot)

    ! nbasis_sym_spin(1,i) gives the number of spin-down basis functions in the i-th
    ! symmetry where i is the bit string describing the irreducible representation.
    ! Similarly, j=2 gives the analagous quantity for spin-up basis functions.
    ! For RHF calculations nbasis_sym_spin(:,i) = nbasis_sym(i)/2.
    integer, allocatable :: nbasis_sym_spin(:,:) ! (2,sym0_tot:sym_max_tot)

    ! sym_spin_basis_fns(:,ims,isym) gives the list of spin functions (ims=1 for
    ! down, ims=2 for up) with symmetry isym.  We merrily waste some memory (not all
    ! symmetries will have the same number of basis functions), so a 0 entry
    ! indicates no more basis functions with the given spin and spatial symmetries.
    integer, allocatable :: sym_spin_basis_fns(:,:,:) ! (max(nbasis_sym_spin),2,sym0_tot:sym_max_tot)

    ! The following masks are used to extract the point-group symmetry from the symmetry of a basis fn.
    ! pg symmetry occupies the lowest bits, and is extracted by iand with this mask.
    integer :: pg_mask  ! Typically 0, 1, 3, or 7 depending on how many point-group operations there are.

    ! Lz symmetry is stored in the higher bits of the symmetry and this mask can be used to access it.
    integer :: Lz_mask

    ! Used to offset the Lz values when encoding into a symmetry.  If iand(sym,Lz_mask)==Lz_offset,
    ! this corresponds to an Lz value of 0.
    integer :: Lz_offset

    ! * or / by Lz_divisor to move the Lz values from higher bits to lower ones.
    ! NB this is not used in time-critical applications, so needn't be a shift rather than *,/
    ! To extract an Lz value from a symmetry sym, use (iand(sym,Lz_mask)-Lz_offset)/Lz_divisor
    ! or (better) use pg_sym_getLz().
    integer :: Lz_divisor
end type pg_sym_t

type mom_sym_t
    ! Index of the symmetry corresponding to the Gamma-point, or if periodic real system the
    ! symmetry corresponding to gamma sym itself.
    integer(int_64) :: gamma_sym

    ! sym_table(i,j) = k means that k_i + k_j = k_k to within a primitive reciprocal lattice vector.
    ! Only used for Hubbard model.
    integer, allocatable :: sym_table(:,:) ! (nsym, nsym)

    ! inv_sym(i) = j means that k_i + k_j = 0 (ie k_j is the inverse of k_i).
    ! Only used for Hubbard model.
    integer, allocatable :: inv_sym(:) ! nsym

    ! Index of gamma point in real periodic systems.
    integer :: gamma_point(3) = [0, 0, 0]
    ! Dimensions of supercell used in translationally symmetric systems.
    ! Used only in read_in translationally symmetric systems.
    integer :: nprop(3) = [0, 0, 0]

    ! Bit length of each symmetry property within isym for translationally
    ! symmetric systems.
    ! Used only in read_in translationally symmetric systems.
    integer :: propbitlen = 0

    ! Number of bands per kpoint. Only used for read_in periodic systems.
    integer :: nbands
    ! Indexes of basis' of sym index. Done by spatial index, assuming using RHF.
    ! Only used for read_in periodic systems.
    integer, allocatable :: basis_sym(:,:) ! nsym, nbands
end type mom_sym_t

contains

    subroutine dealloc_pg_sym_t(pg_sym)

        ! Deallocate all allocated components of pg_sym.

        ! In/Out:
        !   pg_sym: pg_sym_t object to deallocate.

        type(pg_sym_t), intent(inout) :: pg_sym

        if (allocated(pg_sym%nbasis_sym)) deallocate(pg_sym%nbasis_sym)
        if (allocated(pg_sym%nbasis_sym_spin)) deallocate(pg_sym%nbasis_sym_spin)
        if (allocated(pg_sym%sym_spin_basis_fns)) deallocate(pg_sym%sym_spin_basis_fns)

    end subroutine dealloc_pg_sym_t

    subroutine dealloc_mom_sym_t(mom_sym)

        ! Deallocate all allocated components of mom_sym.

        ! In/Out:
        !   mom_sym: mom_sym_t object to deallocate.

        type(mom_sym_t), intent(inout) :: mom_sym

        if (allocated(mom_sym%sym_table)) deallocate(mom_sym%sym_table)
        if (allocated(mom_sym%inv_sym)) deallocate(mom_sym%inv_sym)
        if (allocated(mom_sym%basis_sym)) deallocate(mom_sym%basis_sym)

    end subroutine dealloc_mom_sym_t

end module symmetry_types
