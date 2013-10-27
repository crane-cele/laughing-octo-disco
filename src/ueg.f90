module ueg_system

! Core routines for the uniform electron gas system.

use const

implicit none

! basis_fns stores the basis functions as a list ordered by the kinetic energy
! of the wavefunction.  This is inconvenient for the UEG where we need to find
! a given basis function from the sum of two other wavevectors.
! ueg_basis_lookup(ind) returns the index of the alpha spin-orbital with
! wavevector, k,  in the basis_fns array, where ind is defined by a function
! which considers a cube of wavevectors:
!   ind = (k_x + kmax) + (k_y + kmax)*N_kx + (k_z + kmax)*N_kx^2 + 1
!       = k_x + k_y*N_kx + k_z*N_kx*N_z + k_max*(1 + N_kx + N_kx^2) + 1
! (and analogously for the 2D case), where:
!    kmax is the maximum component of a wavevector in the smallest square/cube
!    which contains all the wavevectors in the basis.
!    N_kx is the number of k-points in each dimension
integer, allocatable :: ueg_basis_lookup(:) ! (N_kx^ndim)

! ueg_basis_dim = (1, N_kx, N_kx^2), so that
!    ind = ueg_basis_dim.k + ueg_basis_origin
! for ueg_basis_lookup.
integer, allocatable :: ueg_basis_dim(:) ! (ndim)

! ueg_basis_origin accounts for the fact that ueg_basis_lookup is a 1-indexed array.
! ueg_basis_origin = k_max*(1 + N_x + N_x*N_y) + 1
integer :: ueg_basis_origin

! Max component of a wavevector in the UEG basis set, kmax.
! Note that N_x = 2*kmax+1
integer :: ueg_basis_max

! When creating an arbitrary excitation, k_i,k_j->k_a,k_b, we must conserve
! crystal momentum, k_i+k_j-k_a-k_b=0.  Hence once we've chosen k_i, k_j and
! k_a, k_b is uniquely defined.  Further, once we've chosen k_i and k_j and if
! we require k_b to exist in the basis, then only certain values of k_a are
! permitted.  ueg_ternary_conserve(0,i,j) gives how many k_a are permitted for
! a given k_i and k_j and ueg_ternary_conserve(1,i,j) gives a bit string with
! only bytes set corresponding to permitted k_a values.  Note only basis
! functions corresponding to *alpha* orbitals are set.  Finally, we use
! tri_ind((j+1)/2,(i+1)/2), j>=i, to store only the lower triangular section of
! the array and only store it for one set of spin functions.
! (j+1)/2 gives the same value for the indices of both alpha and beta basis
! functions of the same wavevector.
! TODO: reduce this to minimum memory required (several k_i+k_j will have the
! same value!).
integer(i0), allocatable :: ueg_ternary_conserve(:,:) ! (0:basis_length,nbasis/2*(nbasis/2+1)/2)

abstract interface

    ! UEG-specific integral procedure pointers.
    ! The integral routines are different for 2D and UEG.  Abstract them using
    ! procedure pointers.
    pure function i_int_ueg(i, a) result(intgrl)
        import :: p
        real(p) :: intgrl
        integer, intent(in) :: i, a
    end function i_int_ueg

end interface

procedure(i_int_ueg), pointer :: coulomb_int_ueg => null()
procedure(i_int_ueg), pointer :: exchange_int_ueg => null()

contains

!-------
! Initialisation, utilities and finalisation

    subroutine init_ueg_proc_pointers(ndim)

        ! Initialise UEG procedure pointers

        ! In:
        !    ndim: dimensionality of the UEG.

        use system
        use errors, only: stop_all

        integer, intent(in) :: ndim

        ! Set pointers to integral routines
        select case(ndim)
        case(2)
            coulomb_int_ueg => coulomb_int_ueg_2d
        case(3)
            coulomb_int_ueg => coulomb_int_ueg_3d
        case default
            call stop_all('init_ueg_proc_pointers', 'Can only do 2D and 3D UEG.')
        end select

        ! For now, we don't treat exchange integrals differently.
        exchange_int_ueg => coulomb_int_ueg

    end subroutine init_ueg_proc_pointers

    subroutine init_ueg_indexing(sys)

        ! Create arrays and data for index mapping needed for UEG.

        ! In:
        !    sys: UEG system to be studied.

        use basis, only: basis_fns, nbasis, bit_lookup, basis_length
        use system, only: sys_t

        use checking, only: check_allocate
        use utils, only: tri_ind

        type(sys_t), intent(in) :: sys

        integer :: ierr, i, j, a, ind, N_kx, k_min(sys%lattice%ndim), bit_pos, bit_el, k(sys%lattice%ndim)

        ueg_basis_max = ceiling(sqrt(2*sys%ueg%ecutoff))

        N_kx = 2*ueg_basis_max+1

        allocate(ueg_basis_dim(sys%lattice%ndim), stat=ierr)
        call check_allocate('ueg_basis_dim', sys%lattice%ndim, ierr)
        forall (i=1:sys%lattice%ndim) ueg_basis_dim(i) = N_kx**(i-1)

        ! Wish the indexing array to be 1-indexed.
        k_min = -ueg_basis_max ! Bottom corner of grid.
        ueg_basis_origin = -dot_product(ueg_basis_dim, k_min) + 1

        allocate(ueg_basis_lookup(N_kx**sys%lattice%ndim), stat=ierr)
        call check_allocate('ueg_basis_lookup', N_kx**sys%lattice%ndim, ierr)

        ! ueg_basis_lookup should be -1 for any wavevector that is in the
        ! square/cubic grid defined by ueg_basis_max but not in the actual basis
        ! set described by ecutoff.
        ueg_basis_lookup = -1

        ! Now fill in the values for the alpha orbitals which are in the basis.
        forall (i=1:nbasis:2) ueg_basis_lookup(dot_product(basis_fns(i)%l, ueg_basis_dim) + ueg_basis_origin) = i

        ! Now fill in the values for permitted k_a in an excitation
        ! k_i,k_j->k_a,k_b, given a choice of k_i ad k_j and requiring k_b is in
        ! the basis.
        allocate(ueg_ternary_conserve(0:basis_length, nbasis/2*(nbasis/2+1)/2), stat=ierr)
        call check_allocate('ueg_ternary_conserve', size(ueg_ternary_conserve), ierr)
        ueg_ternary_conserve = 0_i0
        do i = 2, nbasis, 2
            do j = i, nbasis, 2
                ind = tri_ind(j/2,i/2)
                do a = 1, nbasis-1, 2 ! only alpha orbitals
                    k = basis_fns(i)%l + basis_fns(j)%l - basis_fns(a)%l
                    if (real(dot_product(k,k),p)/2 - sys%ueg%ecutoff < 1.e-8) then
                        ! There exists an allowed b in the basis!
                        ueg_ternary_conserve(0,ind) = ueg_ternary_conserve(0,ind) + 1
                        bit_pos = bit_lookup(1, a)
                        bit_el = bit_lookup(2, a)
                        ueg_ternary_conserve(bit_el,ind) = ibset(ueg_ternary_conserve(bit_el,ind), bit_pos)
                    end if
                end do
            end do
        end do

    end subroutine init_ueg_indexing

    pure function ueg_basis_index(k, spin) result(indx)

        ! In:
        !    k: wavevector in units of 2\pi/L.
        !    spin: 1 for alpha orbital, -1 for beta orbital
        ! Returns:
        !    Index of basis function in the (energy-ordered) basis_fns array.
        !    Set to < 0 if the spin-orbital described by k and spin is not in the
        !    basis set.

        use system

        integer :: indx
        integer, intent(in) :: k(sys_global%lattice%ndim), spin

        if (minval(k) < -ueg_basis_max .or. maxval(k) > ueg_basis_max) then
            indx = -1
        else
            ! ueg_basis_lookup contains the mapping between a wavevector in
            ! a given basis and its entry in the energy-ordered list of basis
            ! functions.
            indx = ueg_basis_lookup(dot_product(k,ueg_basis_dim) + ueg_basis_origin)
            ! ueg_basis_lookup only contains entries for the alpha spin-orbital.
            ! The corresponding beta orbital is the next entry in the basis_fns
            ! array.
            if (spin < 0) indx = indx + 1
        end if

    end function ueg_basis_index

    subroutine end_ueg_indexing()

        ! Clean up UEG index arrays.

        use checking, only: check_deallocate

        integer :: ierr

        if (allocated(ueg_basis_lookup)) then
            deallocate(ueg_basis_lookup, stat=ierr)
            call check_deallocate('ueg_basis_lookup', ierr)
        end if
        if (allocated(ueg_basis_dim)) then
            deallocate(ueg_basis_dim, stat=ierr)
            call check_deallocate('ueg_basis_dim', ierr)
        end if
        if (allocated(ueg_ternary_conserve)) then
            deallocate(ueg_ternary_conserve, stat=ierr)
            call check_deallocate('ueg_ternary_conserve', ierr)
        end if

    end subroutine end_ueg_indexing

!-------
! Integrals

    pure function get_two_e_int_ueg(i, j, a, b) result(intgrl)

        ! In:
        !    i,j:  index of the spin-orbital from which an electron is excited in
        !          the reference determinant.
        !    a,b:  index of the spin-orbital into which an electron is excited in
        !          the excited determinant.
        !
        ! Returns:
        !   The anti-symmetrized integral < ij || ab >.

        ! Warning: assume i,j /= a,b (ie not asking for < ij || ij > or < ij || ji >).

        use basis, only: basis_fns

        real(p) :: intgrl
        integer, intent(in) :: i, j, a, b

        intgrl = 0.0_p

        ! Crystal momentum conserved?
        if (all(basis_fns(i)%l + basis_fns(j)%l - basis_fns(a)%l - basis_fns(b)%l == 0)) then

            ! Spin conserved?

            ! Coulomb
            if (basis_fns(i)%ms == basis_fns(a)%ms .and.  basis_fns(j)%ms == basis_fns(b)%ms) &
                intgrl = intgrl + coulomb_int_ueg(i, a)

            ! Exchange
            if (basis_fns(i)%ms == basis_fns(b)%ms .and.  basis_fns(j)%ms == basis_fns(a)%ms) &
                intgrl = intgrl - coulomb_int_ueg(i, b)

        end if

    end function get_two_e_int_ueg

    pure function coulomb_int_ueg_2d(i, a) result(intgrl)

        ! In:
        !    i: index of spin-orbital basis function.
        !    a: index of spin-orbital basis function.
        !
        ! Returns:
        !    The Coulumb integral < i j | a b > = 2\pi/\Omega|k_i - k_a| for the 2D
        !    UEG.  Note that we assume i, j, a and b are such that spin and
        !    crystal momentum is conserved and hence the integral is not zero by
        !    symmetry.  We also assume that i,j /= a,b (ie the integral is not
        !    a Hartree integral).

        use basis, only: basis_fns
        use system

        real(p) :: intgrl
        integer, intent(in) :: i, a
        integer :: q(2)

        ! Wavevectors are stored in units of 2\pi/L, where L is the length of
        ! the cell.  As we only deal with cubic simulation cells (i.e. \Omega = L^2),
        ! the integral hence becomes 1/(L|q|), where q = k_i - k_a.

        q = basis_fns(i)%l - basis_fns(a)%l
        intgrl = 1.0_p/(sys_global%lattice%box_length(1)*sqrt(real(dot_product(q,q),p)))

    end function coulomb_int_ueg_2d

    pure function coulomb_int_ueg_3d(i, a) result(intgrl)

        ! In:
        !    i: index of spin-orbital basis function.
        !    a: index of spin-orbital basis function.
        !
        ! Returns:
        !    The Coulumb integral < i j | a b > = 1/|k_i - k_a|^2 for the 3D
        !    UEG.  Note that we assume i, j, a and b are such that spin and
        !    crystal momentum is conserved and hence the integral is not zero by
        !    symmetry.  We also assume that i,j /= a,b (ie the integral is not
        !    a Hartree integral).

        use basis, only: basis_fns
        use system

        real(p) :: intgrl
        integer, intent(in) :: i, a
        integer :: q(3)

        ! Wavevectors are stored in units of 2\pi/L, where L is the length of
        ! the cell.  As we only deal with cubic simulation cells (i.e. \Omega = L^3),
        ! the integral hence becomes 1/(\pi.L.q^2), where q = k_i - k_a.

        q = basis_fns(i)%l - basis_fns(a)%l
        intgrl = 1.0_p/(pi*sys_global%lattice%box_length(1)*dot_product(q,q))

    end function coulomb_int_ueg_3d

end module ueg_system
