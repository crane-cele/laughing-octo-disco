#ifdef USE_POPCNT
module popcnt_intrinsic
    ! Module which can be used along to rename the F2008 popcnt intrinsic.
    intrinsic popcnt
end module popcnt_intrinsic
#endif

module bit_utils

! Module for bit utilities.

! Mainly mainipulate variables of type integer(i0) on a bit-wise basis
! as these are used in storing determinants.

use const

#ifdef USE_POPCNT
use popcnt_intrinsic, only: count_set_bits=>popcnt
#endif

implicit none

interface operator(.bitstrge.)
    module procedure bit_str_32_ge
    module procedure bit_str_64_ge
end interface

interface operator(.bitstrgt.)
    module procedure bit_str_32_gt
    module procedure bit_str_64_gt
end interface

interface bit_str_cmp
    module procedure bit_str_32_cmp
    module procedure bit_str_64_cmp
end interface

#ifndef USE_POPCNT
interface count_set_bits
    module procedure count_set_bits_int_32
    module procedure count_set_bits_int_64
end interface
#endif

interface count_even_set_bits
    module procedure count_even_set_bits_int_32
    module procedure count_even_set_bits_int_64
end interface

interface bit_str_lshift_pad
    module procedure bit_str_32_lshift_pad
    module procedure bit_str_64_lshift_pad
end interface

contains

!--- Counting set bits ---

    elemental function naive_count_set_bits(b) result(nbits)

        ! In:
        !    b: bit string stored as an integer(i0)
        ! Returns:
        !    The number of bits set in  b.
        ! This is an exceptionally naive implementation and should only be used
        ! for testing more optimal versions.

        integer :: nbits
        integer(i0), intent(in) :: b
        integer :: i

        nbits = 0
        do i = 0, i0_end
            if (btest(b, i)) nbits = nbits + 1
        end do

    end function naive_count_set_bits

    elemental function count_set_bits_int_32(b) result(nbits)

        ! In:
        !    b: A 32-bit integer.
        ! Returns:
        !    The number of set bits in b.

        ! This uses a branch-free algorithm.  See comments below for details.

        integer :: nbits
        integer(int_32), intent(in) :: b
        integer(int_32) :: tmp

        ! For 32 bit integers:
        integer(int_32), parameter :: m1 = int(Z'55555555',int_32)
        integer(int_32), parameter :: m2 = int(Z'33333333',int_32)
        integer(int_32), parameter :: m3 = int(Z'0F0F0F0F',int_32)
        integer(int_32), parameter :: m4 = int(Z'01010101',int_32)

        ! This is quite cool.

        ! For a more detailed explanation and discussion see:
        !   http://everything2.com/title/Counting+1+bits
        !   http://graphics.stanford.edu/~seander/bithacks.html
        !   http://gurmeetsingh.wordpress.com/2008/08/05/fast-bit-counting-routines/
        !   Chapter 5 of the excellent Hacker's Delight by Henry S. Warren.

        ! The general idea is to use a divide and conquer approach.
        ! * Set each 2 bit field to be the sum of the set bits in the two single
        !   bits originally in that field.
        ! * Set each 4 bit field to be the sum of the set bits in the two 2 bit
        !   fields originally in the 4 bit field.
        ! * Set each 8 bit field to be the sum of the set bits in the two 4 bit
        !   fields it contains.
        ! * etc.
        ! Thus we obtain an algorithm like:
        !     x = ( x & 01010101...) + ( (x>>1) & 01010101...)
        !     x = ( x & 00110011...) + ( (x>>2) & 00110011...)
        !     x = ( x & 00001111...) + ( (x>>4) & 00001111...)
        ! etc., where & indicates AND and >> is the shift right operator.
        ! Further optimisations are:
        ! * Any & operations can be omitted where there is no danger that
        !   a field's sum will carry over into the next field.
        ! * The first line can be replaced by:
        !     x = x - ( (x>>1) & 01010101...)
        !   thanks to the population (number of set bits) in an integer
        !   containing p bits being given by:
        !     pop(x) = \sum_{i=0}^{p-1} x/2^i
        ! * Summing 8 bit fields together can be performed via a multiplication
        !   followed by a right shift.
        ! Thus the following (extremely fast) algorithms.

        ! For 32 bit integers:
        tmp = b
        tmp = tmp - iand(ishft(tmp,-1), m1)
        tmp = iand(tmp, m2) + iand(ishft(tmp,-2), m2)
        tmp = iand((tmp + ishft(tmp,-4)), m3)*m4
        nbits = ishft(tmp, -24)

    end function count_set_bits_int_32

    elemental function count_set_bits_int_64(b) result(nbits)

        ! In:
        !    b: A 64-bit integer.
        ! Returns:
        !    The number of set bits in b.

        ! This is the 64-bit equivalent of count_set_bits_int_32; see comments there for
        ! more details.

        integer :: nbits
        integer(int_64), intent(in) :: b
        integer(int_64) :: tmp

        ! For 64 bit integers:
        integer(int_64), parameter :: m1 = int(Z'5555555555555555',int_64)
        integer(int_64), parameter :: m2 = int(Z'3333333333333333',int_64)
        integer(int_64), parameter :: m3 = int(Z'0f0f0f0f0f0f0f0f',int_64)
        integer(int_64), parameter :: m4 = int(Z'0101010101010101',int_64)

        tmp = b
        tmp = tmp - iand(ishft(tmp,-1), m1)
        tmp = iand(tmp, m2) + iand(ishft(tmp,-2), m2)
        tmp = iand(tmp, m3) + iand(ishft(tmp,-4), m3)
        ! Note conversion is safe as 0 <= nbits <= 64.
        nbits = int(ishft(tmp*m4, -56))

    end function count_set_bits_int_64

    elemental function count_even_set_bits_int_32(b) result(neven)

        ! In:
        !    b: A 32-bit integer.
        ! Returns:
        !    The number of even set bits in b.

        integer :: neven
        integer(int_32), intent(in) :: b
        integer(int_32), parameter :: m = int(Z'55555555',int_32)

        neven = count_set_bits(iand(b,m))

    end function count_even_set_bits_int_32

    elemental function count_even_set_bits_int_64(b) result(neven)

        ! In:
        !    b: A 64-bit integer.
        ! Returns:
        !    The number of even set bits in b.

        integer :: neven
        integer(int_64), intent(in) :: b
        integer(int_64), parameter :: m = int(Z'5555555555555555',int_64)

        neven = count_set_bits(iand(b,m))

    end function count_even_set_bits_int_64

!--- I/O helpers ---

    elemental function bit_string(b) result(s)

        ! In:
        !    b: bit string stored as an integer(i0)
        ! Returns:
        !    A binary representation of the bit string as a character string.

        character(i0_length) :: s
        integer(i0), intent(in) :: b
        character(10) :: bit_fmt

        ! This is good for integers containing less than 1000 bits.
        ! Producing the format string each time is non-optimal, but this is only
        ! i/o.
        ! The format is something like (B8.8), which gives a bit string of
        ! length 8 and forces all 8 bits to be written (including leading 0s).
        write (bit_fmt,'("(B",I3,".",I3,")")') i0_length, i0_length

        write (s,bit_fmt) b

    end function bit_string

!--- Permutations of set bits in bit string ---

    function first_perm(n) result(p)

        ! In:
        !    n: number of bits to set.
        ! Returns:
        !    i0 bit string containing the lexicographically first permutation of n set bits.

        integer(i0) :: p
        integer, intent(in) :: n
        integer :: i

        p = 0
        do i = 0, n-1
            p = ibset(p,i)
        end do

    end function first_perm

    function bit_permutation(v) result(w)

        ! In:
        !    v: a bit string.
        ! Returns:
        !    The next permutation of the bit string in lexicographic order.
        !
        !    As we store the bit strings as i0 integers, overflow is possible,
        !    i.e. with 10 spin functions and 5 electrons, bit_permuation can
        !    return bits set in the 11th and higher sites.  Fortunately this
        !    only happens after all permutations involving just the first 10
        !    sites are exhausted (by design!), so only happens if bit_permuation
        !    is called too many times...

        integer(i0) :: w
        integer(i0), intent(in) :: v
        integer(i0) :: t1, t2

        ! From http://graphics.stanford.edu/~seander/bithacks.html.

        t1 = ior(v, v-1) + 1
        t2 = ishft(iand(t1,-t1)/iand(v,-v),-1) - 1
        w = ior(t1, t2)

    end function bit_permutation

!--- Converting bit strings ---

    pure subroutine decode_bit_string(b, d)

        ! In:
        !    b: bit string stored as an integer(i0)
        ! Out:
        !    d: list of bits set in b.  It is assumed that d is at least as
        !    large as the number of bits set in b.  If not, then all elements of
        !    d are set to -1.
        !    The bit string is 0-indexed.

        ! See comments in decode_det for a description of the algorithm.

        use bit_table_256_m, only: bit_table_256

        integer(i0), intent(in) :: b
        integer, intent(out) :: d(:)

        integer :: nbits_seen, ifield, nfound
        integer(i0) :: offset, field

        integer, parameter :: field_size = ubound(bit_table_256, dim=1)
        integer, parameter :: nfields = i0_length/field_size
        integer(i0), parameter :: mask = 2**field_size - 1

        nfound = 0
        offset = 0
        ! 1-based index in lookup table, but bits in Fortran are indexed from 0.
        nbits_seen = -1
        do ifield = 1, nfields
            ! Inspect one byte at a time.
            field = iand(mask, ishft(b, -offset))
            associate(in_field=>bit_table_256(0,field))
                d(nfound+1:nfound+in_field) = bit_table_256(1:in_field, field) + nbits_seen
                nfound = nfound + in_field
            end associate
            offset = offset + field_size
            nbits_seen = nbits_seen + field_size
        end do

    end subroutine decode_bit_string

!--- Comparison of bit strings---

    pure function bit_str_32_ge(b1, b2) result(ge)

        ! In:
        !    b1(:), b2(:) bit string.
        ! Returns:
        !    True if all(b1 == b2) or the most significant element of b1 which
        !    is not equal to the corresponding element of b2 is bitwise greater
        !    than the corresponding element in b2.

        logical :: ge
        integer(int_32), intent(in) :: b1(:), b2(:)

        integer :: i

        ge = .true.
        do i = ubound(b1,dim=1), 1, -1
            if (bgt(b1(i),b2(i))) then
                ge = .true.
                exit
            else if (blt(b1(i),b2(i))) then
                ge = .false.
                exit
            end if
        end do

    end function bit_str_32_ge

    pure function bit_str_64_ge(b1, b2) result(ge)

        ! In:
        !    b1(:), b2(:) bit string.
        ! Returns:
        !    True if all(b1 == b2) or the most significant element of b1 which
        !    is not equal to the corresponding element of b2 is bitwise greater
        !    than the corresponding element in b2.

        logical :: ge
        integer(int_64), intent(in) :: b1(:), b2(:)

        integer :: i

        ge = .true.
        do i = ubound(b1,dim=1), 1, -1
            if (bgt(b1(i),b2(i))) then
                ge = .true.
                exit
            else if (blt(b1(i),b2(i))) then
                ge = .false.
                exit
            end if
        end do

    end function bit_str_64_ge

    pure function bit_str_32_gt(b1, b2) result(gt)

        ! In:
        !    b1(:), b2(:) bit string.
        ! Returns:
        !    True if the most significant element of b1 which is not equal to
        !    the corresponding element of b2 is bitwise greater than the
        !    corresponding element in b2.

        logical :: gt
        integer(int_32), intent(in) :: b1(:), b2(:)

        integer :: i

        gt = .false.
        do i = ubound(b1,dim=1), 1, -1
            if (bgt(b1(i),b2(i))) then
                gt = .true.
                exit
            else if (blt(b1(i),b2(i))) then
                gt = .false.
                exit
            end if
        end do

    end function bit_str_32_gt

    pure function bit_str_64_gt(b1, b2) result(gt)

        ! In:
        !    b1(:), b2(:) bit string.
        ! Returns:
        !    True if the most significant element of b1 which is not equal to
        !    the corresponding element of b2 is bitwise greater than the
        !    corresponding element in b2.

        logical :: gt
        integer(int_64), intent(in) :: b1(:), b2(:)

        integer :: i

        gt = .false.
        do i = ubound(b1,dim=1), 1, -1
            if (bgt(b1(i),b2(i))) then
                gt = .true.
                exit
            else if (blt(b1(i),b2(i))) then
                gt = .false.
                exit
            end if
        end do

    end function bit_str_64_gt


    pure function bit_str_32_cmp(b1, b2) result(cmp)

        ! In:
        !    b1(:), b2(:): bit string.
        ! Returns:
        !    0 if b1 and b2 are identical;
        !    1 if the most significant non-identical element in b1 is bitwise
        !      less than the corresponding element in b2;
        !    -1 if the most significant non-identical element in b1 is bitwise
        !      greater than the corresponding element in b2;

        integer :: cmp
        integer(int_32), intent(in) :: b1(:), b2(:)

        integer :: i

        cmp = 0
        do i = ubound(b1, dim=1), 1, -1
            if (blt(b1(i),b2(i))) then
                cmp = 1
                exit
            else if (bgt(b1(i),b2(i))) then
                cmp = -1
                exit
            end if
        end do

    end function bit_str_32_cmp

    pure function bit_str_64_cmp(b1, b2) result(cmp)

        ! In:
        !    b1(:), b2(:): bit string.
        ! Returns:
        !    0 if b1 and b2 are identical;
        !    1 if the most significant non-identical element in b1 is bitwise
        !      less than the corresponding element in b2;
        !    -1 if the most significant non-identical element in b1 is bitwise
        !      greater than the corresponding element in b2;

        integer :: cmp
        integer(int_64), intent(in) :: b1(:), b2(:)

        integer :: i

        cmp = 0
        do i = ubound(b1, dim=1), 1, -1
            if (blt(b1(i),b2(i))) then
                cmp = 1
                exit
            else if (bgt(b1(i),b2(i))) then
                cmp = -1
                exit
            end if
        end do

    end function bit_str_64_cmp

    pure subroutine bit_str_32_lshift_pad(f, lshift, f_shift)

        ! This is a generic function to left shift an int_32 array and pad 1's to the right.

        ! In:
        !    f(:): the int_32 array to be shifted.
        !    lshift: the amount of left shift to do.
        ! Out:
        !    f_shift(:): the shifted int_32 array.

        integer(int_32), intent(in) :: f(:)
        integer, intent(in) :: lshift
        integer(int_32), intent(out) :: f_shift(:)

        integer :: nbasis, new_str_len, ierr, bit_el_shft, bit_pos_shft, bit_el_orig, bit_pos_orig, bsize, i

        bsize = bit_size(0_int_32)

        ! The upper bound to the number of basis functions
        nbasis = size(f_shift) * bsize

        f_shift(:) = 0_int_32

        do i = 0, nbasis-1
            ! i starts at 0, so integer division (round towards 0) has the correct behaviour
            bit_el_shft = i/bsize + 1
            bit_pos_shft = mod(i, bsize)
            if (i <= lshift-1) then
                ! Just set the padding bit
                f_shift(bit_el_shft) = ibset(f_shift(bit_el_shft), bit_pos_shft)
            else
                ! Copy the bit from f to f_shift
                bit_el_orig = (i-lshift)/bsize + 1
                bit_pos_orig = mod((i-lshift), bsize)
                if (btest(f(bit_el_orig), bit_pos_orig)) f_shift(bit_el_shft) = ibset(f_shift(bit_el_shft), bit_pos_shft)
            end if
        end do

    end subroutine bit_str_32_lshift_pad

    pure subroutine bit_str_64_lshift_pad(f, lshift, f_shift)

        ! This is a generic function to left shift an int_64 array and pad 1's to the right.

        ! In:
        !    f(:): the int_64 array to be shifted.
        !    lshift: the amount of left shift to do.
        ! Out:
        !    f_shift(:): the shifted int_64 array.

        integer(int_64), intent(in) :: f(:)
        integer, intent(in) :: lshift
        integer(int_64), intent(out) :: f_shift(:)

        integer :: nbasis, new_str_len, ierr, bit_el_shft, bit_pos_shft, bit_el_orig, bit_pos_orig, bsize, i

        bsize = bit_size(0_int_64)

        ! The upper bound to the number of basis functions
        nbasis = size(f_shift) * bsize

        f_shift(:) = 0_int_64

        do i = 0, nbasis-1
            ! i starts at 0, so integer division (round towards 0) has the correct behaviour
            bit_el_shft = i/bsize + 1
            bit_pos_shft = mod(i, bsize)
            if (i <= lshift-1) then
                ! Just set the padding bit
                f_shift(bit_el_shft) = ibset(f_shift(bit_el_shft), bit_pos_shft)
            else
                ! Copy the bit from f to f_shift
                bit_el_orig = (i-lshift)/bsize + 1
                bit_pos_orig = mod((i-lshift), bsize)
                if (btest(f(bit_el_orig), bit_pos_orig)) f_shift(bit_el_shft) = ibset(f_shift(bit_el_shft), bit_pos_shft)
            end if
        end do

    end subroutine bit_str_64_lshift_pad

end module bit_utils
