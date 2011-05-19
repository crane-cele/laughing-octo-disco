module symmetry

implicit none

! Stored symmetry information *only* for the Hubbard model.  UEG symmetry is
! done on the fly due to the size of the basis---see ueg module.

! Number of symmetries.
! Currently only crystal momentum is implemented.
integer :: nsym

! Index of the symmetry corresponding to the Gamma-point.
integer :: gamma_sym

! sym_table(i,j) = k means that k_i + k_j = k_k to within a primitive reciprocal lattice vector.
integer, allocatable :: sym_table(:,:) ! (nsym, nsym)

! inv_sym(i) = j means that k_i + k_j = 0 (ie k_j is the inverse of k_i).
integer, allocatable :: inv_sym(:) ! nsym

contains

    subroutine init_symmetry()

        ! Construct the symmetry tables.

        use basis, only: nbasis, basis_fns, write_basis_fn
        use system, only: ndim, system_type, hub_real, hub_k, ueg
        use kpoints, only: is_reciprocal_lattice_vector
        use parallel, only: parent
        use utils, only: int_fmt
        use checking, only: check_allocate
        use errors, only: stop_all
        use ueg_system, only: init_ueg_indexing

        integer :: i, j, k, ierr
        integer :: ksum(ndim)
        character(4) :: fmt1

        select case(system_type)
        case(hub_real)

            ! Symmetry currently not implemented.
            nsym = 1

        case(hub_k)

            ! Each wavevector corresponds to its own irreducible representation.
            ! The maximum system size considered will be quite small (ie <200)
            ! and the sum of any two wavevectors is another wavevector in the
            ! basis (up to a primitive reciprocal lattice vector).
            ! It is thus feasible to store the nsym^2 product table.

            nsym = nbasis/2
            allocate(sym_table(nsym, nsym), stat=ierr)
            call check_allocate('sym_table',nsym*nsym,ierr)
            allocate(inv_sym(nsym), stat=ierr)
            call check_allocate('inv_sym',nsym,ierr)

            fmt1 = int_fmt(nsym)

            gamma_sym = 0
            do i = 1, nsym
                if (all(basis_fns(i*2)%l == 0)) gamma_sym = i
            end do
            if (gamma_sym == 0) call stop_all('init_symmetry', 'Gamma-point symmetry not found.')

            do i = 1, nsym
                do j = i, nsym
                    ksum = basis_fns(i*2)%l + basis_fns(j*2)%l
                    do k = 1, nsym
                        if (is_reciprocal_lattice_vector(ksum - basis_fns(k*2)%l)) then
                            sym_table(i,j) = k
                            sym_table(j,i) = k
                            if (k == gamma_sym) then
                                inv_sym(i) = j
                                inv_sym(j) = i
                            end if
                            exit
                        end if
                    end do
                end do
            end do

            if (parent) then
                write (6,'(1X,a20,/,1X,20("-"),/)') "Symmetry information"
                write (6,'(1X,a63,/)') 'The table below gives the label and inverse of each wavevector.'
                write (6,'(1X,a5,4X,a7)', advance='no') 'Index','k-point'
                do i = 1, ndim
                    write (6,'(3X)', advance='no')
                end do
                write (6,'(a7)') 'Inverse'
                do i = 1, nsym
                    write (6,'(i4,5X)', advance='no') i
                    call write_basis_fn(basis_fns(2*i), new_line=.false., print_full=.false.)
                    write (6,'(5X,i4)') inv_sym(i)
                end do
                write (6,'()')
                write (6,'(1X,a83,/)') &
                    "The matrix below gives the result of k_i+k_j to within a reciprocal lattice vector."
                do i = 1, nsym
                    do j = 1, nsym
                        write (6,'('//fmt1//')', advance='no') sym_table(j,i)
                    end do
                    write (6,'()')
                end do
                write (6,'()')
            end if

        case(ueg)

            ! Trickier.
            ! No primitive reciprocal lattice and thus a secondary basis eight
            ! times larger than the basis used is required to span all
            ! possible k_i+k_j combinations.  As we wish to do calculations on
            ! basis sets containing 1000s of wavevectors, it is not feasible to
            ! store the product table as we do for the Hubbard model.

            ! Instead, we have a function which produces an index for a given
            ! k-point and a mapping array which converts that index to the index
            ! of the energy-ordered basis set.  The symmetry is then done on the
            ! fly.

            call init_ueg_indexing()

        end select

    end subroutine init_symmetry

    subroutine end_symmetry

        ! Clean up after symmetry.

        use ueg_system, only: end_ueg_indexing
        use checking, only: check_deallocate

        integer :: ierr

        if (allocated(sym_table)) then
            deallocate(sym_table, stat=ierr)
            call check_deallocate('sym_table',ierr)
        end if
        if (allocated(inv_sym)) then
            deallocate(inv_sym, stat=ierr)
            call check_deallocate('inv_sym',ierr)
        end if

        call end_ueg_indexing()

    end subroutine end_symmetry

end module symmetry
