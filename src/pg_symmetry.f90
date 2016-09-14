module point_group_symmetry

! Module for handling point group symmetry, as read in from molecular FCIDUMP
! files.

! This was made much easier thanks to conversations with Alex Thom...

! NOTE:
! It seems physicists are far less obsessed with point group symmetries than my
! undergraduate chemistry course.  I recommend a thorough reading of the
! relevant sections of the classic book 'Group Theory and Quantum Mechanics' by
! Tinkham.

! It is best to avoid directly handling the symmetry yourself and instead use the
! functions in this module, abelian_symmetry.f90 or more generally pointers within
! sys%read_in. This enables flexibility in case L_z symmetry or translational
! symmetry is being used.

! Point group symmetry
! --------------------
!
! The quantum chemistry packages we use to generate FCIDUMP files only implement
! D2h symmetry (and subgroups thereof).  Whilst this means some symmetries are
! not considered, the advantage for us is that all point groups we will consider
! are real and Abelian.  Thus:
!
! * all irreducible representations are 1D.
! * all operations are their own inverse
! * \Gamma_i \cross \Gamma_i = \Gamma_1, where \Gamma_i is an arbitrary
!   irreducible representation, \cross indicates direct product and \Gamma_1 is
!   the totally-symmetric representation.
! * all irreducible representations can be represented by (at most) three
!   generators and the behaviour of a function under those generators is
!   sufficient to completely determine the symmetry of that function.
!
! Furthermore, we assume that each basis function spans one (and only one)
! irreducible representation---this can always be done when working in D2h (or
! a subgroup thereof).
!
! An irreducible representation is labelled by its behaviour under the
! generators of the point group using a bit string where the i-th bit
! corresponds to the i-th generator.  A set bit indicates that the
! representation is *odd* with respect to that generator and an unset bit
! indicates that the representation is *even* with respect to that generator.
! Thus the totally symmetric representation is always labelled by the 0 bit
! string.
!
! Direct products are easily evaluated by considering the characters of the
! generator operations in the product: even \cross even = even, odd \cross odd = even
! and odd \cross even = odd.  Hence the direct product can be found by
! taking XOR of the representations involved.
!
! As we consider (at most) D2h (3 generators) we can just use a standard integer
! to represent the irreducible representations.  The higher bits are wasted unless
! used for Lz symmetry information, but the memory used is minimal.
!
! For a point group containing n generators, there are 2^n irreducible
! representations.  Due to the bit representation described above, these
! representations are labelled by the set of integers {0,1,...2^n-1}.

! L_z symmetry
! ------------

! If L_z is also conserved (note: requires orbital transformation; see user manual), then
! the higher bits of the symmetry label are used for this information.

! However, L_z does not form a closed group.  We take a pragmatic view and store the minimum
! number of symmetries which we can encounter during a calculation.  This occurs when requiring
! L_z to be conserved in a four-index integral, which fixes the value of L_z for the 4th index
! given the values for the first three indices.  Hence we need to consider 3 maxLz, where maxLz
! is the maximum value of L_z in the basis.

! NOTE: L_z information is stored with an offset for ease of storage and extraction.  See below
! for details.

use const

implicit none

contains

    subroutine init_pg_symmetry(sys, hdf5)

        ! Initialise point group symmetry information.
        ! *Must* be called after basis functions are initialised and have their
        ! symmetries set from the FCIDUMP file.

        ! In (optional):
        !    hdf5: logical determining whether initiating system from hdf5 file.
        !       In this case basis function symmetry doesn't need to be updated.
        ! In/Out:
        !    sys: system being studied.  On output the symmetry fields are set.

        use checking, only: check_allocate

        use system, only: sys_t

        logical, intent(in), optional :: hdf5

        type(sys_t), intent(inout) :: sys

        integer :: i, ierr, ims, ind

        integer :: maxsym, maxLz

        logical :: hdf5_loc

        hdf5_loc = .false.
        if (present(hdf5)) hdf5_loc = hdf5


        ! molecular systems use symmetry indices starting from 0.
        sys%sym0 = 0

        ! Given n generators, there must be 2^n irreducible representations.
        ! in the working space.  (Note that the wavefunctions might only span
        ! a subspace of the point group considered by the generating quantum
        ! chemistry package.)
        ! Set maxsym to be 2^n so that we always work in the smallest group
        ! spanned by the wavefunctions.
        ! +1 comes from the fact that the basis_fn%sym gives the bit string
        ! representation.

        maxsym = 2**ceiling(log(real(maxval(sys%basis%basis_fns(:)%sym)+1))/log(2.0))

        if(sys%read_in%useLz) then
            ! This is the Max Lz value we find in the basis functions.
            maxLz = maxval(sys%basis%basis_fns(:)%lz)
        else
            maxLz = 0 ! Let's not use Lz.
        endif
        ! The point group mask is used to extract the point group symmetry from a sym.
        ! Since the point group sym goes from 0..maxsym-1, and maxsym is always a power
        ! of 2, the mask is just maxsym-1
        if (hdf5_loc) then
            maxsym = sys%read_in%pg_sym%pg_mask + 1
        else
            sys%read_in%pg_sym%pg_mask = maxsym-1
        end if
        ! We'll put Lz in higher bits, and an encode or decode by multiplying or diviging by:
        sys%read_in%pg_sym%Lz_divisor = maxsym

        ! When we use excitation generators, we combine together at most three orbitals'
        ! symmetries. The maximum encountered value of Lz will therefore be maxLz*3 
        ! (and the minimum the negative of this).
        ! We allocate bits for this above the pointgroup symmetry bits.
        ! If using renormalized excitation generators, we iterate over all possible symmetries
        ! so we wish to keep the number of symmetries as low as possible.  We therefore
        ! compromise on allowing Lz values from -3*MaxLz ... 3*MaxLz, which will
        ! be stored in the higher bits of the sym using this mask.
        sys%read_in%pg_sym%Lz_mask = (2**ceiling(log(real(6*maxLz+1))/log(2.0))-1)*sys%read_in%pg_sym%Lz_divisor
        ! However, in order to store these, two's complement is not a good idea as it does
        ! not provide a continuous set of numbers (e.g. in three bits, -1,0,1 would render
        ! as 111,000,001, and if these are stored as the higher bits of symmetry, they would
        ! provide too many symmetries to iterate over.
        ! e.g. if we had a single point-group bit, the allowed symmetries would be
        ! 1110, 1111, 0000, 0001, 0010, 0011 which are not continuous integers (when stored 32-bit)
        ! (unless we sign extend - I didn't want to get into that.)
        ! To make things continuous, we add Lz_offset to the Lz value so it always becomes positive.
        ! e.g. here, we would want to offset Lz by 1 (to get 0,1,2) so we set Lz_offset to 
        ! 0010 (putting it in the right place in the bit string), giving symmetries:
        ! 0000, 0001, 0010, 0011, 0100, 0101 which are continuous integers.
        ! For reference in Lz world, 0 means Lz=-3*maxLz*maxsym, so Lz_offset means Lz=0
        sys%read_in%pg_sym%Lz_offset = 3*maxLz*sys%read_in%pg_sym%Lz_divisor
        sys%read_in%pg_sym%gamma_sym = sys%read_in%pg_sym%Lz_offset

        if(sys%symmetry < huge(0)) then
            ! If one wished to specify Lz in sys%symmetry, it would be added in here.
            ! Need to modify to include Lz:
            sys%symmetry = sys%symmetry + sys%read_in%pg_sym%Lz_offset
        else if (sys%tot_sym) then
            sys%symmetry = sys%read_in%pg_sym%gamma_sym
        endif

        ! nsym, sym0 and sym_max allow one to iterate over the symmetries that occur in
        ! the basis fns:
        sys%sym0 = iand((-maxLz*sys%read_in%pg_sym%Lz_divisor+sys%read_in%pg_sym%Lz_offset),sys%read_in%pg_sym%Lz_mask)
        sys%sym_max = maxLz*sys%read_in%pg_sym%Lz_divisor+sys%read_in%pg_sym%Lz_offset+maxsym-1
        sys%nsym = sys%sym_max - sys%sym0
        ! We can iterate from sys%sym0 .. sys%sym_max, which following the above discussion means
        sys%sym0_tot = 0
        sys%nsym_tot = (6*maxLz+1)*sys%read_in%pg_sym%Lz_divisor
        sys%sym_max_tot = sys%nsym_tot-1

        allocate(sys%read_in%pg_sym%nbasis_sym(sys%sym0_tot:sys%sym_max_tot), stat=ierr)
        call check_allocate('sys%read_in%pg_sym%nbasis_sym', sys%nsym_tot, ierr)
        allocate(sys%read_in%pg_sym%nbasis_sym_spin(2,sys%sym0_tot:sys%sym_max_tot), stat=ierr)
        call check_allocate('sys%read_in%pg_sym%nbasis_sym_spin', 2*sys%nsym_tot, ierr)

        sys%read_in%pg_sym%nbasis_sym = 0
        sys%read_in%pg_sym%nbasis_sym_spin = 0

        associate(nbasis=>sys%basis%nbasis, basis_fns=>sys%basis%basis_fns)
            do i = 1, nbasis
                ! Encode the Lz into the symmetry. We shift the lz into higher bits (by *maxsym)  and offset.
                if (maxLz>0 .and. .not. hdf5_loc) then
                    basis_fns(i)%sym = basis_fns(i)%sym + &
                        (basis_fns(i)%lz*sys%read_in%pg_sym%Lz_divisor+sys%read_in%pg_sym%Lz_offset)
                endif
                sys%read_in%pg_sym%nbasis_sym(basis_fns(i)%sym) = sys%read_in%pg_sym%nbasis_sym(basis_fns(i)%sym) + 1

                if (.not.hdf5_loc) basis_fns(i)%sym_index = sys%read_in%pg_sym%nbasis_sym(basis_fns(i)%sym)

                ims = (basis_fns(i)%Ms+3)/2 ! Ms=-1,1 -> ims=1,2

                sys%read_in%pg_sym%nbasis_sym_spin(ims,basis_fns(i)%sym) = &
                            sys%read_in%pg_sym%nbasis_sym_spin(ims,basis_fns(i)%sym) + 1
                if (.not. hdf5_loc) then
                    basis_fns(i)%sym_spin_index = sys%read_in%pg_sym%nbasis_sym_spin(ims,basis_fns(i)%sym)
                end if
            end do
        end associate

        allocate(sys%read_in%pg_sym%sym_spin_basis_fns(maxval(sys%read_in%pg_sym%nbasis_sym_spin),2,sys%sym0_tot:sys%sym_max_tot), &
                    stat=ierr)
        call check_allocate('sys%read_in%pg_sym%sym_spin_basis_fns', &
                            maxval(sys%read_in%pg_sym%nbasis_sym_spin)*2*sys%nsym_tot, ierr)
        sys%read_in%pg_sym%sym_spin_basis_fns = 0

        do i = 1, sys%basis%nbasis
            ims = (sys%basis%basis_fns(i)%Ms+3)/2 ! Ms=-1,1 -> ims=1,2
            ind = minloc(sys%read_in%pg_sym%sym_spin_basis_fns(:,ims,sys%basis%basis_fns(i)%sym), dim=1) ! first non-zero element
            sys%read_in%pg_sym%sym_spin_basis_fns(ind, ims, sys%basis%basis_fns(i)%sym) = i
        end do

        sys%read_in%cross_product_sym_ptr => cross_product_pg_sym
        sys%read_in%sym_conj_ptr => pg_sym_conj

    end subroutine init_pg_symmetry

    subroutine print_pg_symmetry_info(sys)

        ! Write out point group symmetry information.

        ! In:
        !    sys: system being studied.

        use system, only: sys_t
        use parallel, only: parent
        use utils, only: int_fmt

        type(sys_t), intent(in) :: sys

        integer :: i, j, sym

        if (parent) then
            write (6,'(1X,a20,/,1X,20("-"),/)') "Symmetry information"

            write(6,'(1X,"Number of point group symmetries:",'//int_fmt(sys%read_in%pg_sym%Lz_divisor,1)//')') &
                    sys%read_in%pg_sym%Lz_divisor
            if(sys%read_in%useLz) then
                ! This is the Max Lz value we find in the basis functions.
                i = maxval(sys%basis%basis_fns(:)%lz)
                write(6,'(1X,"Maximum Lz found:",'//int_fmt(i,1)//')') i
                write(6,'(1X,"Lz offset (corresponds to Lz=0):",'//int_fmt(sys%read_in%pg_sym%Lz_offset,1)//')') &
                    sys%read_in%pg_sym%Lz_offset
            else
                write(6,'(1X,"Not using Lz symmetry.")')
            endif
            write(6,'(1X,"Totally symmetric symmetry:",'//int_fmt(sys%read_in%pg_sym%gamma_sym,1)//')') sys%read_in%pg_sym%gamma_sym
            write (6,'(1X,a78,/)') 'The matrix below gives the direct products of the irreducible representations.'
            ! Note that we never actually store this.
            do i = sys%sym0, sys%sym_max
                do j = sys%sym0, sys%sym_max
                    sym=cross_product_pg_sym(sys%read_in,i,j)
                    if (sym>=sys%sym0_tot.and.sym<sys%nsym_tot) then
                        write (6,'(1X,i2)',advance='no') sym
                    else
                        write (6,'(3X)',advance='no')
                    endif
                end do
                write (6,'()')
            end do

            write (6,'(/,1X,a93,/)') 'The table below gives the number of basis functions spanning each irreducible representation.'

            write (6,'(1X,"irrep  Lz   sym  nbasis  nbasis_up  nbasis_down")')
            do i = sys%sym0, sys%sym_max
                write (6,'(1X,i3,3X,i3,3X,i2,2X,i5,3X,i5,6X,i5)') i, pg_sym_getLz(sys%read_in%pg_sym, i), &
                    iand(i,sys%read_in%pg_sym%pg_mask), &
                    sys%read_in%pg_sym%nbasis_sym(i), sys%read_in%pg_sym%nbasis_sym_spin(:,i)
            end do

            write (6,'()')

        end if

    end subroutine print_pg_symmetry_info

    pure function cross_product_pg_sym(read_in, sym_i, sym_j) result(sym_ij)

        ! In:
        !    read_in: information on the symmetries of the basis functions.
        !    sym_i,sym_j: bit string representations of irreducible
        !                 representations of a point group and Lz symmetry
        ! Returns:
        !    The bit string representation of the irreducible representation
        !    formed from the direct product sym_i \cross sym_j.
        !    The Lz part of the symmetry is split off and handled separately from the
        !    rest, and then reintegrated.

        use system, only: sys_read_in_t

        integer :: sym_ij
        integer, intent(in) :: sym_i, sym_j
        type(sys_read_in_t), intent(in) :: read_in

        ! The pg part can be done with an exclusive or. To save on operations, we mask after that.
        ! The Lz is just additive (though we need to extract it and remember to remove an offset).
        associate(pg_sym=>read_in%pg_sym)
            sym_ij = ior(iand(ieor(sym_i, sym_j),pg_sym%pg_mask), &
                    iand(sym_i,pg_sym%Lz_mask)+iand(sym_j,pg_sym%Lz_mask)-pg_sym%Lz_offset)
        end associate

    end function cross_product_pg_sym

    pure function pg_sym_conj(read_in, sym) result(rsym)

        ! In:
        !   read_in: information on the symmetries of the basis functions.
        !   sym: the bit representation of the irrep of the pg sym including
        !        Lz in its higher bits 
        ! Returns:
        !   The symmetry conjugate of the symmetry. For pg symmetry this is the same as
        !   it's Abelian, but we need to take Lz to -Lz here.

        use system, only: sys_read_in_t

        type(sys_read_in_t), intent(in) :: read_in
        integer, intent(in) :: sym
        integer :: rsym

        ! Take the symmetry conjugate.  The point group part is the same.
        ! The Lz needs to become -Lz but also dealing with the offsetting.
        rsym  = ior(iand(sym,read_in%pg_sym%pg_mask), &
                iand(2*read_in%pg_sym%Lz_offset-iand(sym,read_in%pg_sym%Lz_mask), &
                read_in%pg_sym%Lz_mask))

    end function pg_sym_conj

    elemental function pg_sym_getLz(pg_sym, sym) result(Lz)

        ! In:
        !    pg_sym: information on the symmetries of the basis functions.
        !    sym: bit string representation of an irreducible representation of
        !    a point group.
        ! Returns:
        !    The Lz component of sym (de-offsetted), so Lz=0 is returned as 0

        use symmetry_types, only: pg_sym_t

        type(pg_sym_t), intent(in) :: pg_sym
        integer, intent(in) :: sym
        integer :: Lz
        Lz = (iand(sym,pg_sym%Lz_mask)-pg_sym%Lz_offset)/pg_sym%Lz_divisor

    end function pg_sym_getLz

end module point_group_symmetry
