module utils

! Various utilities and tools...

implicit none

contains

    elemental function binom_i(m, n) result(binom)

        ! ACM Algorithm 160 translated to Fortran.
        ! Returns the binomial coefficient ^mC_n: the number of
        ! combinations of m things taken n at a time.

        integer :: binom
        integer, intent(in) :: m, n
        integer :: p,i, n1

        n1 = n
        p = m - n1
        if (n1 < p) then
            p = n1
            n1 = m - p
        end if
        binom = n1 + 1
        if (p == 0) binom = 1
        do i = 2, p
            binom = (binom*(n1+i))/i
        end do

    end function binom_i

    elemental function binom_r(m, n) result(binom)

        ! ACM Algorithm 160 translated to Fortran.
        ! Returns the binomial coefficient ^mC_n: the number of
        ! combinations of m things taken n at a time.

        use const, only: dp

        real(dp) :: binom
        integer, intent(in) :: m, n
        integer :: p,i, n1

        n1 = n
        p = m - n1
        if (n1 < p) then
            p = n1
            n1 = m - p
        end if
        binom = n1 + 1
        if (p == 0) binom = 1
        do i = 2, p
            binom = (binom*(n1+i))/i
        end do

    end function binom_r

    elemental function factorial_combination_1(m,n) result (combination)

        ! Given m and n input, this function returns
        ! combination = n!m!/(n+m+1)!
        ! Required to calculate amplitudes of the Neel singlet
        ! trial function for the Heisenberg model

        use const, only: dp

        real(dp) :: combination
        integer, intent(in) :: m, n
        integer :: m1, n1, i

        ! Choose m1 to be the larger of m and n
        if (m >= n) then
            m1 = m
            n1 = n
        else
            m1 = n
            n1 = m
        end if
        combination = 1
        do i = 1, n1
            combination = combination * i/(i+m1)
        end do
        combination = combination/(m1+n1+1)

    end function factorial_combination_1

    function get_free_unit() result(free_unit)

        ! Returns:
        !    The first free file unit above 10 and less than or equal to
        !    the paramater max_unit (currently set to 200).

        use errors, only: stop_all

        integer, parameter :: max_unit = 100
        integer :: free_unit
        integer :: i
        logical :: t_open, t_exist

        do i = 10, max_unit
            inquire(unit=i, opened=t_open, exist=t_exist)
            if (.not.t_open .and. t_exist) then
                free_unit = i
                exit
            end if
        end do
        if (i == max_unit+1) call stop_all('get_free_unit','Cannot find a free unit below max_unit.')

    end function get_free_unit

    elemental function int_fmt(i, padding) result(fmt1)

        ! In:
        !    i: an integer
        !    padding (optional): amount of padding to add to format statement.
        !        The default amount is 2.  The padding is used to include the
        !        sign if i is negative.
        ! Returns:
        !    fmt1: a format statement for an integer field which will hold
        !        i perfectly plus an amount of padding.

        ! This does take i/o formatting to a slightly OCD level addmittedly...

        character(4) :: fmt1
        integer, intent(in) :: i
        integer, intent(in), optional :: padding
        integer :: p
        real :: r

        if (present(padding)) then
            p = padding
        else
            p  = 2
        end if

        if (i == 0 .or. i==1) then
            r = 1.0
        else
            r = log10(real(abs(i)+1))
        end if
        p = ceiling(r+p)

        if (p < 10) then
            write (fmt1,'("i",i1)') p
        else if (p < 100) then
            write (fmt1,'("i",i2)') p
        else
            ! By this point we'll have hit integer overflow anyway...
            write (fmt1,'("i",i3)') p
        end if

    end function int_fmt

    subroutine append_ext(stem, n, s)

        ! Returns stem.n in s.

        character(*), intent(in) :: stem
        integer, intent(in) :: n
        character(*), intent(out) :: s
        character(10) :: ext

        write (ext,'('//int_fmt(n,0)//')') n
        s = stem//'.'//ext

    end subroutine append_ext

   subroutine get_unique_filename(stem, tnext, istart, filename)

        ! Find a filename which is either the "newest" or the next to be used.
        ! The filename is assumed to be stem.x, where x is an integer.

        ! In:
        !    stem: stem of the filename.
        !    tnext: the next unused filename is found if true, else the
        !        filename is set to be stem.x where stem.x exists and stem.x+1
        !        doesn't and x is greater than istart.
        !    istart: the integer of the first x value to check.
        !        If istart is negative, then the filename is set to be stem.x,
        !        where x = |istart+1|.  This overrides everything else.
        ! Out:
        !    filename.

        character(*), intent(in) :: stem
        logical, intent(in) :: tnext
        integer, intent(in) :: istart
        character(*), intent(out) :: filename

        integer :: i
        logical :: exists

        i = istart
        exists = .true.
        do while (exists)
            call append_ext(stem, i, filename)
            inquire(file=filename,exist=exists)
            i = i + 1
        end do

        if (.not.tnext) then
            ! actually want the last file which existed.
            ! this will return stem.istart if stem.istart doesn't exist.
            i = max(istart,i - 2)
            call append_ext(stem, i, filename)
        end if

        ! Have been asked for a specific file.
        if (istart < 0) then
            call append_ext(stem, abs(istart+1), filename)
        end if

    end subroutine get_unique_filename

    elemental function tri_ind(i,j) result(indx)

        ! Find the index corresponding to the (i,j)-th element of a lower
        ! triangular array.  This maps:
        !
        !   1,1                   1
        !   2,1 2,2               2  3
        !   3,1 3,2 3,3       to  4  5  6
        !   4,1 4,2 4,3 4,4       7  8  9 10
        !
        ! WARNING:
        ! We assume that i >= j.  It is the programmer's responsibility to check
        ! this and re-order i and j if required.
        !
        ! In:
        !    i: (1-indexed) row index
        !    j: (1-indexed) column index
        ! Returns:
        !    A combined (1-indexed) index for the corresponding element in
        !    a lower triangular array.

        integer :: indx
        integer, intent(in) :: i, j

        indx = ((i-1)*i)/2 + j

    end function tri_ind

    elemental function tri_ind_reorder(i,j) result(indx)

        ! Find the index corresponding to the (i,j)-th element of a lower
        ! triangular array.
        !
        ! We assume that i >= j.  If this is not the case (i.e. (i,j) refers to
        ! an element in the upper triangular array) then the index of the
        ! transpose element (i.e. (j,i)) is returned.
        !
        ! This maps:
        !
        !   1,1 1,2 1,3 1,4        1  2  4  7
        !   2,1 2,2 2,3 2,4        2  3  5  8
        !   3,1 3,2 3,3 3,4   to   4  5  6  9
        !   4,1 4,2 4,3 4,4        7  8  9 10
        !
        ! In:
        !    i: (1-indexed) index
        !    j: (1-indexed) index
        ! Returns:
        !    A combined (1-indexed) index for the corresponding element in
        !    a lower triangular array.

        integer :: indx
        integer, intent(in) :: i, j

        if (i>=j) then
            indx = tri_ind(i,j)
        else
            indx = tri_ind(j,i)
        end if

    end function tri_ind_reorder

    pure function fstring_to_carray(string_f03) result(array_c)

        ! Convert a Fortran string into a C string.  The result can be passed to
        ! C procedures which require a *char object, which corresponds to an
        ! array in Fortran.

        ! In:
        !    string_f03: Fortran character string.
        ! Returns:
        !    The equivalent (null-terminated) C string in a character array.

        use, intrinsic :: iso_c_binding, only: c_char, c_null_char

        character(len=*), intent(in) :: string_f03
        character(kind=c_char) :: array_c(len(string_f03)+1)

        integer :: i

        do i = 1, len(string_f03)
            array_c(i) = string_f03(i:i)
        end do
        array_c(i) = c_null_char

    end function fstring_to_carray

    pure function carray_to_fstring(array_c) result(string_f03)

        ! Convert a C string into a Fortran string.  The input can be from a
        ! C procedure which uses a *char object (which corresponds to an array
        ! in Fortran) and the output is the equivalent standard Fortran string.

        ! In:
        !    array_c: null-terminated C string in a character array.
        ! Returns:
        !    The equivalent Fortran character string (without null termination).

        use, intrinsic :: iso_c_binding, only: c_char, c_null_char

        character(kind=c_char), intent(in) :: array_c(:)
        character(len=size(array_c)-1) :: string_f03

        integer :: i

        ! Don't copy any (presumably garbage) from beyond the null character.
        string_f03 = ''
        do i = 1, size(array_c)-1
            if (array_c(i) == c_null_char) exit
            string_f03(i:i) = array_c(i)
        end do

    end function carray_to_fstring

end module utils
