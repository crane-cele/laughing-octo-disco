module molecular_integrals

! Module for storing and accessing integrals for molecular systems.
! These integrals are previously calculated using a quantum chemistry package
! (e.g. MOLPRO or QChem).

! TODO:
! * (compile-time option) allocate arrays using shmem.

use const, only: p
use base_types, only: alloc_rp1d

implicit none

! Indexing type for two_body integral stores.
type int_indx
    integer :: spin_channel, indx
end type

! Interaction with integral stores is best done using the store_* and get_*
! procedures provided below rather than directly accessing them.

! Store for one-body integrals, <i|o|j>, where i,j are spin basis functions and
! o is a one-electron operator.
type one_body
    ! integrals(ispin, isym)%v(indx) corresponds to the <i|o|j> integral (assuming
    ! i,j conserve spin and spatial symmetry), where ispin and isym index the spin
    ! and spatial symmetry of i and j and indx is the combined (triangular) index of
    ! i and j within that spin and symmetry block.
    ! See access procedures for this in practice.
    ! This data structure makes it possible and relative easy to only store the
    ! integrals which are non-zero by symmetry (ie a small fraction of the possible
    ! integrals).
    ! Note that only one spin channel is needed (and stored) in RHF calculations.
    type(alloc_rp1d), allocatable :: integrals(:,:)
    ! bit string representations of irreducible representations
    integer :: op_sym
end type

! Store for two-body integrals, <ij|o|ab>, where i,j,a,b are spin basis functions and
! o is a two-electron operator.
type two_body
    ! integrals(ispin)%v(indx) gives the integral <ij|o_2|ab>, where ispin depends upon
    ! the spin combination (ie all alpha, all beta, and haf alpha, half beta) and
    ! indx is related to i,j,a,b.  As we deal with real orbitals only, we can use
    ! permutation symmetry to reduce the number of integrals by a factor of 8.
    ! See access procedures for this in action.
    ! Note that only one spin channel is needed (and stored) in RHF calculations.
    ! TODO:
    ! * can compress coulomb integral store by ensuring integrand is totally
    !   symmetric, as is done for the one-body integrals.
    type(alloc_rp1d), allocatable :: integrals(:)
    ! bit string representations of irreducible representations
    integer :: op_sym
end type

! Store for <i|h|j>, where h is the one-electron Hamiltonian operator.
type(one_body) :: one_e_h_integrals

! Store for the two-body integrals, <ij|1/r_12|ab>, where i,j,a,b are spin basis
! functions and 1/r_12 is the Coulomb operator.
type(two_body) :: coulomb_integrals

contains

!--- Memory allocation and deallocation ---

    subroutine init_one_body_int_store(op_sym, store)

        ! Allocate memory required for the integrals involving a one-body
        ! operator.

        ! In:
        !    op_sym: bit string representations of irreducible representations
        !    of a point group.  See point_group_symmetry.
        ! Out:
        !    store: one-body integral store with components allocated to hold
        !    interals.  Note that the integral store is *not* zeroed. 

        use basis, only: nbasis
        use point_group_symmetry, only: nbasis_sym_spin
        use system, only: uhf

        use checking, only: check_allocate

        integer, intent(in) :: op_sym
        type(one_body), intent(out) :: store

        integer :: ierr, i, s, ispin, nspin

        store%op_sym = op_sym

        ! if rhf then need to store only integrals for spatial orbitals.
        ! ie < i,alpha j,beta | a,alpha b,beta > = < i,alpha j,alpha | a,alpha b,alpha >
        if (uhf) then
            nspin = 2
        else
            nspin = 1
        end if

        ! Allocate general store for the one-electron integrals.
        allocate(store%integrals(nspin,lbound(nbasis_sym_spin, dim=2):ubound(nbasis_sym_spin, dim=2)), stat=ierr)
        call check_allocate('one_body_store', size(store%integrals), ierr)

        ! <i|o|j> is only non-zero if the integrand is totally symmetric, ie
        ! \Gamma_i \cross \Gamma_o \cross \Gamma_j = \Gamma_1.
        ! Currently all operators we consider are Hermitian.
        ! => Store only lower triangle of each symmetry block in o_{ij}.
        ! Within the block each state is labelled by its symmetry and spin
        ! index.  If \Gamma_o \= \Gamma_1, then i and j are of different
        ! symmetries.  We get around this by arranging index_i=<index_j.  In this
        ! case some memory is wasted (as we store the diagonal elements in both
        ! the i and j symmetry blocks) and if the number of states with the same 
        ! symmetry as i is greater than those with with same symmetry as j, but
        ! this effect will be small.
        !
        ! o_{ij} is only non-zero if i and j are of the same spin.
        ! Furthermore, o_{i,alpha, j,alpha} = o_{i,beta, j, beta} in RHF
        ! calculations.
        ! => store spin blocks separately and only store both in UHF
        ! calculations.
        do ispin = 1, nspin
            do i = lbound(store%integrals, dim=2), ubound(store%integrals, dim=2)
                s = (nbasis_sym_spin(ispin,i)*(nbasis_sym_spin(ispin,i)+1))/2
                allocate(store%integrals(ispin,i)%v(s), stat=ierr)
                call check_allocate('one_body_store_component', s, ierr)
            end do
        end do

    end subroutine init_one_body_int_store

    subroutine end_one_body_int_store(store)

        ! Deallocate components of a store of integrals involving a one-body operator.

        ! In/Out:
        !    store: one-body integral store with components allocated to hold
        !    integrals which are deallocated upon exit.

        use checking, only: check_deallocate

        type(one_body), intent(inout) :: store
        integer :: i, ierr, ispin

        if (allocated(store%integrals)) then
            do ispin = lbound(store%integrals, dim=1), ubound(store%integrals, dim=1)
                do i = lbound(store%integrals, dim=2), ubound(store%integrals, dim=2)
                    deallocate(store%integrals(ispin,i)%v, stat=ierr)
                    call check_deallocate('one_body_store_component', ierr)
                end do
            end do
            deallocate(store%integrals, stat=ierr)
            call check_deallocate('one_body_store', ierr)
        end if

    end subroutine end_one_body_int_store

    subroutine init_two_body_int_store(op_sym, store)

        ! Allocate memory required for the integrals involving a two-body
        ! operator.

        ! In:
        !    op_sym: bit string representations of irreducible representations
        !    of a point group.  See point_group_symmetry.
        ! Out:
        !    store: two-body integral store with components allocated to hold
        !    interals.  Note that the integral store is *not* zeroed. 

        use basis, only: nbasis
        use point_group_symmetry, only: nbasis_sym_spin
        use system, only: uhf

        use checking, only: check_allocate

        integer, intent(in) :: op_sym
        type(two_body), intent(out) :: store

        integer :: ierr, ispin
        integer :: nspin, npairs, nintgrls

        store%op_sym = op_sym

        ! if rhf then need to store only integrals for spatial orbitals.
        ! ie < i,alpha j,beta | a,alpha b,beta > = < i,alpha j,alpha | a,alpha b,alpha >
        if (uhf) then
            nspin = 4
        else
            nspin = 1
        end if

        ! Allocate general store for each spin-channel the two-electron integrals.
        allocate(store%integrals(nspin), stat=ierr)
        call check_allocate('two_body_store', nspin**2, ierr)

        ! Allocate component of store for each spin-channel.
        ! The spatial parts are identical in RHF, thus need store only one
        ! spin-channel.
        ! In UHF need to store <a a|a a>, <a b|a b>, <b a|b a> and <b b|b b>
        ! (where a==alpha spin-orbital and b==beta spin-orbital).
        ! For the integral <i j|a b>, where (i,j,a,b) are spatial-orbitals,
        ! there are M(M+1)/2=N_p (i,a) pairs (and similarly for (j,b) pairs).
        ! Due to permutation symmetry there are thus N_p(N_p+1)/2 integrals per
        ! spin-channel, where 2M is the number of spin-orbitals.
        ! NOTE:
        ! Compression due to spatial symmetry not yet implemented.
        npairs = ((nbasis/2)*(nbasis/2 + 1))/2
        nintgrls = (npairs*(npairs+1))/2
        do ispin = 1, nspin
            allocate(store%integrals(ispin)%v(nintgrls), stat=ierr)
            call check_allocate('two_body_store_component', nintgrls, ierr)
        end do

    end subroutine init_two_body_int_store

    subroutine end_two_body_int_store(store)

        ! Deallocate comptwonts of a store of integrals involving a two-body operator.

        ! In/Out:
        !    store: two-body integral store with comptwonts allocated to hold
        !    integrals which are deallocated upon exit.

        use checking, only: check_deallocate

        type(two_body), intent(inout) :: store
        integer :: ierr, ispin

        if (allocated(store%integrals)) then
            do ispin = lbound(store%integrals, dim=1), ubound(store%integrals, dim=1)
                deallocate(store%integrals(ispin)%v, stat=ierr)
                call check_deallocate('two_body_store_component', ierr)
            end do
            deallocate(store%integrals, stat=ierr)
            call check_deallocate('two_body_store', ierr)
        end if

    end subroutine end_two_body_int_store

!--- Allocate standard molecular integral stores ---

    subroutine init_molecular_integrals()

        ! Initialise integral stores for molecular integrals (subsequently read
        ! in from an FCIDUMP file).

        ! *Must* be called after point group symmetry is initialised.

        use point_group_symmetry, only: gamma_sym

        call init_one_body_int_store(gamma_sym, one_e_h_integrals)
        call init_two_body_int_store(gamma_sym, coulomb_integrals)

    end subroutine init_molecular_integrals

    subroutine end_molecular_integrals()

        ! Deallocate arrays containing molecular integrals.

        call end_one_body_int_store(one_e_h_integrals)
        call end_two_body_int_store(coulomb_integrals)

    end subroutine end_molecular_integrals

!--- Integral access ---

! TODO:
! fast and specific 'get' functions for UHF and RHF cases

! 1. < i | o_1 | j >

    subroutine store_one_body_int_mol(i, j, intgrl, store)

        ! Store <i|o_1|j> in the appropriate slot in the one-body integral
        ! store.  The store does not have room for non-zero integrals, so it is
        ! assumed that <i|o_1|j> is non-zero by spin and spatial symmetry.
        !
        ! In:
        !    i,j: (indices of) spin-orbitals.
        !    intgrl: <i|o_1|j>, where o_1 is a one-body operator.
        ! In/out:
        !    store: one-body integral store.  On exit the <i|o_1|j> is also
        !    stored.

        use basis, only: basis_fns
        use point_group_symmetry, only: cross_product_pg_basis, cross_product_pg_sym, is_gamma_irrep_pg_sym
        use system, only: uhf

        use const, only: depsilon
        use errors, only: stop_all
        use utils, only: tri_ind

        integer, intent(in) :: i, j
        real(p), intent(in) :: intgrl
        type(one_body) :: store

        integer :: ii, jj, spin
        integer :: sym
        character(255) :: error

        sym = cross_product_pg_basis(i, j)
        sym = cross_product_pg_sym(sym, store%op_sym)

        if (is_gamma_irrep_pg_sym(sym) .and. basis_fns(i)%ms == basis_fns(j)%ms) then

            ! Integral is (should be!) non-zero by symmetry.
            if (uhf) then
                if (basis_fns(i)%ms > 0) then
                    spin = 1
                else
                    spin = 2
                end if
            else
                spin = 1
            end if
            ii = basis_fns(i)%sym_spin_index
            jj = basis_fns(j)%sym_spin_index
            if (ii == jj) then
                ! See note about how operators which are no symmetric are
                ! handled in init_one_body_int_store.
                store%integrals(spin,basis_fns(i)%sym)%v(tri_ind(ii,jj)) = intgrl
                store%integrals(spin,basis_fns(j)%sym)%v(tri_ind(jj,ii)) = intgrl
            else if (ii > jj) then
                store%integrals(spin,basis_fns(i)%sym)%v(tri_ind(ii,jj)) = intgrl
            else
                store%integrals(spin,basis_fns(j)%sym)%v(tri_ind(jj,ii)) = intgrl
            end if
        else if (abs(intgrl) > depsilon) then
            write (error, '("<i|o|j> should be non-zero by symmetry: &
                            &<",i3,"|o|",i3,"> =",f16.10)') i, j, intgrl
            call stop_all('store_one_body_int_mol', error)
        end if

    end subroutine store_one_body_int_mol

    pure function get_one_body_int_mol(store, i, j) result(intgrl)

        ! In:
        !    store: one-body integral store.
        !    i,j: (indices of) spin-orbitals.
        ! Returns:
        !    <i|o|j>, the corresponding one-body matrix element, where o is a
        !    one-body operator given by store.
        !
        ! NOTE:
        !    If <i|o|j> is known the be non-zero by spin and spatial symmetry,
        !    then it is faster to call get_one_body_int_mol_nonzero.
        !    It is also faster to call RHF- or UHF-specific routines.

        use basis, only: basis_fns
        use point_group_symmetry, only: cross_product_pg_basis, cross_product_pg_sym, is_gamma_irrep_pg_sym

        real(p) :: intgrl
        type(one_body), intent(in) :: store
        integer, intent(in) :: i, j

        integer :: sym

        sym = cross_product_pg_basis(i, j)
        sym = cross_product_pg_sym(sym, store%op_sym)

        if (is_gamma_irrep_pg_sym(sym) .and. basis_fns(i)%ms == basis_fns(j)%ms) then
            intgrl = get_one_body_int_mol_nonzero(store, i, j)
        else
            intgrl = 0.0_p
        end if

    end function get_one_body_int_mol

    pure function get_one_body_int_mol_nonzero(store, i, j) result(intgrl)

        ! In:
        !    store: one-body integral store.
        !    i,j: (indices of) spin-orbitals.
        ! Returns:
        !    <i|o|j>, the corresponding one-body matrix element, where o is a
        !    one-body operator given by store.
        !
        ! NOTE:
        !    This assumes that <i|h|j> is known the be non-zero by spin and
        !    spatial symmetry.  If this is not true then this routine will return
        !    either an incorrect value or cause an array-bounds error.  If
        !    <i|h|j> might be zero by symmetry, get_one_body_int_mol must be called
        !    instead.
        !    It is faster to call RHF- or UHF-specific routines.

        use basis, only: basis_fns
        use system, only: uhf

        use utils, only: tri_ind

        real(p) :: intgrl
        type(one_body), intent(in) :: store
        integer, intent(in) :: i, j

        integer :: ii, jj, spin

        if (uhf) then
            if (basis_fns(i)%ms > 0) then
                spin = 1
            else
                spin = 2
            end if
        else
            spin = 1
        end if
        ii = basis_fns(i)%sym_spin_index
        jj = basis_fns(j)%sym_spin_index

        if (ii >= jj) then
            intgrl = store%integrals(spin, basis_fns(i)%sym)%v(tri_ind(ii,jj))
        else
            intgrl = store%integrals(spin, basis_fns(j)%sym)%v(tri_ind(jj,ii))
        end if

    end function get_one_body_int_mol_nonzero

! 2. < i j | o_2 | a b >

    elemental function two_body_int_indx(i, j, a, b) result(indx)

        ! In:
        !    i,j,a,b: (indices of) spin-orbitals.
        ! Returns:
        !    indx: spin-channel and index of a two_body integral store which contains the
        !    <ij|o_2|ab> integral.

        use basis, only: basis_fns
        use system, only: uhf

        use utils, only: tri_ind

        type(int_indx) :: indx
        integer, intent(in) :: i, j, a, b

        integer :: ii, jj, aa, bb, tmp

        ii = i
        jj = j
        aa = a
        bb = b

        ! Use permutation symmetry to find unique integral.
        ! Require i<a and j<b.
        if (ii > aa) then
            tmp = aa
            aa = ii
            ii = tmp
        end if
        if (jj > bb) then
            tmp = bb
            bb = jj
            jj = tmp
        end if
        ! Require (i,a) < (j,b), i.e. i<j || (i==j && a<b)
        if (ii > jj .or. (ii==jj .and. aa > bb) ) then
            tmp = ii
            ii = jj
            jj = tmp
            tmp = aa
            aa = bb
            bb = tmp
        end if

        ! Find spin channel.
        if (uhf) then
            if (basis_fns(ii)%ms == -1) then
                if (basis_fns(jj)%ms == -1) then
                    ! down down down down
                    indx%spin_channel = 1
                else
                    ! down up down up
                    indx%spin_channel = 3
                end if
            else
                if (basis_fns(jj)%ms == 1) then
                    ! up up up up
                    indx%spin_channel = 2
                else
                    ! up down up down
                    indx%spin_channel = 4
                end if
            end if
        else
            indx%spin_channel = 1
        end if

        ! Convert to spatial indices
        ii = basis_fns(ii)%spatial_index
        jj = basis_fns(jj)%spatial_index
        aa = basis_fns(aa)%spatial_index
        bb = basis_fns(bb)%spatial_index

        ! Find index.
        indx%indx = tri_ind(tri_ind(ii,aa),tri_ind(jj,bb))

    end function two_body_int_indx

    subroutine store_two_body_int_mol(i, j, a, b, intgrl, store)

        ! Store <ij|o_2|ab> in the appropriate slot in the two-body integral store.
        ! The store does not have room for non-zero integrals, so it is assumed
        ! that <ij|o_2|ab> is non-zero by spin and spatial symmetry.
        !
        ! (Note that compression by spatial symmetry is currently not
        ! implemented.)
        !
        ! In:
        !    i,j,a,b: (indices of) spin-orbitals.
        !    intgrl: <ij|o_2|ab>, where o_2 is a two-electron operator.  Note
        !    the integral is expressed in *PHYSICIST'S NOTATION*.
        ! In/out:
        !    store: two-body integral store.  On exit the <ij|o_2|ab> is also
        !    stored.

        use basis, only: basis_fns
        use point_group_symmetry, only: cross_product_pg_basis, cross_product_pg_sym, is_gamma_irrep_pg_sym

        use const, only: depsilon
        use errors, only: stop_all

        integer, intent(in) :: i, j, a, b
        real(p), intent(in) :: intgrl
        type(two_body), intent(inout) :: store

        integer :: sym_ij, sym_ab, sym
        type(int_indx) :: indx
        character(255) :: error

        ! Should integral be non-zero by symmetry?
        sym_ij = cross_product_pg_basis(i, j)
        sym_ab = cross_product_pg_basis(a, b)
        sym = cross_product_pg_sym(sym_ij, sym_ab)
        sym = cross_product_pg_sym(sym, store%op_sym)

        if (is_gamma_irrep_pg_sym(sym) .and. basis_fns(i)%ms == basis_fns(a)%ms &
                                       .and. basis_fns(j)%ms == basis_fns(b)%ms) then
            ! Store integral
            indx = two_body_int_indx(i, j, a, b)
            store%integrals(indx%spin_channel)%v(indx%indx) = intgrl
        else if (abs(intgrl) > depsilon) then
            write (error, '("<ij|o|ab> should be non-zero by symmetry: &
                            &<",2i3,"|",2i3,"> =",f16.10)') i, j, a, b, intgrl
            call stop_all('store_two_body_int_mol', error)
        end if

    end subroutine store_two_body_int_mol

    pure function get_two_body_int_mol(store, i, j, a, b) result(intgrl)

        ! In:
        !    store: two-body integral store.
        !    i,j,a,b: (indices of) spin-orbitals.
        ! Returns:
        !    < i j | o_2 | a b >, the integral between the (i,a) co-density and
        !    the (j,b) co-density involving a two-body operator o_2 given by
        !    store.
        !
        ! NOTE:
        !    If <ij|ab> is known the be non-zero by spin and spatial symmetry,
        !    then it is faster to call get_two_body_int_mol_nonzero.
        !    It is also faster to call RHF- or UHF-specific routines.

        use basis, only: basis_fns
        use point_group_symmetry, only: cross_product_pg_basis, cross_product_pg_sym, is_gamma_irrep_pg_sym

        real(p) :: intgrl
        type(two_body), intent(in) :: store
        integer, intent(in) :: i, j, a, b

        integer :: sym_ij, sym_ab, sym

        sym_ij = cross_product_pg_basis(i, j)
        sym_ab = cross_product_pg_basis(a, b)
        sym = cross_product_pg_sym(sym_ij, sym_ab)
        sym = cross_product_pg_sym(sym, store%op_sym)
        if (is_gamma_irrep_pg_sym(sym) .and. basis_fns(i)%ms == basis_fns(a)%ms &
                                       .and. basis_fns(j)%ms == basis_fns(b)%ms) then
            intgrl = get_two_body_int_mol_nonzero(store, i, j, a, b)
        else
            intgrl = 0.0_p
        end if

    end function get_two_body_int_mol

    pure function get_two_body_int_mol_nonzero(store, i, j, a, b) result(intgrl)

        ! In:
        !    store: two-body integral store.
        !    i,j,a,b: (indices of) spin-orbitals.
        ! Returns:
        !    < i j | o_2 | a b >, the integral between the (i,a) co-density and
        !    the (j,b) co-density involving a two-body operator o_2 given by
        !    store.
        !
        ! NOTE:
        !    This assumes that <ij|ab> is known the be non-zero by spin and
        !    spatial symmetry.  If this is not true then this routine will return
        !    either an incorrect value or cause an array-bounds error.  If
        !    <ij|ab> might be zero by symmetry, get_two_body_int_mol must be called
        !    instead.
        !    It is faster to call RHF- or UHF-specific routines.

        use basis, only: basis_fns

        real(p) :: intgrl
        type(two_body), intent(in) :: store
        integer, intent(in) :: i, j, a, b

        type(int_indx) :: indx

        indx = two_body_int_indx(i, j, a, b)
        intgrl = store%integrals(indx%spin_channel)%v(indx%indx)

    end function get_two_body_int_mol_nonzero

end module molecular_integrals
