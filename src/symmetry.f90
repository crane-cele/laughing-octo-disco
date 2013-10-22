module symmetry

! Module for symmetry routines common to all symmetries.

implicit none

! This depends upon system-specific symmetry modules, so take care not to
! introduce circular dependencies by USEing it in the system-specific symmetry
! modules.

! Often routines are just wrappers around the relevant system-specific
! routines.  It is thus more efficient to directly call the system-specific
! routines where possible (e.g. from a system-specific FCIQMC spawning routine).

contains

    pure function symmetry_orb_list(orb_list) result(isym)

        ! In:
        !    orb_list: list of orbitals (e.g. determinant).
        ! Returns:
        !    symmetry index of list (i.e. direct product of the representations
        !    of all the orbitals in the list).

        use momentum_symmetry, only: symmetry_orb_list_hub_k, symmetry_orb_list_ueg
        use point_group_symmetry, only: symmetry_orb_list_mol
        use system

        integer :: isym
        integer, intent(in) :: orb_list(:)

        select case(sys_global%system)
        case(hub_k)
            isym = symmetry_orb_list_hub_k(orb_list)
        case(ueg)
            isym = symmetry_orb_list_ueg(orb_list)
        case(read_in)
            isym = symmetry_orb_list_mol(orb_list)
        case default
            ! symmetry not implemented
            isym = sys_global%sym0
        end select

    end function symmetry_orb_list

    elemental function cross_product(s1, s2) result(prod)

        ! In:
        !    s1, s2: irreducible representation labels/momentum labels/symmetry bit strings
        ! Returns:
        !    s1 \cross s2, the direct product of the two symmetries.

        use point_group_symmetry, only: cross_product_pg_sym
        use momentum_symmetry, only: cross_product_hub_k, cross_product_ueg
        use system

        integer :: prod
        integer, intent(in) :: s1, s2

        select case(sys_global%system)
        case(hub_k)
            prod = cross_product_hub_k(s1, s2)
        case(ueg)
            prod = cross_product_ueg(s1, s2)
        case(read_in)
            prod = cross_product_pg_sym(s1, s2)
        case default
            ! symmetry not implemented
            prod = sys_global%sym0
        end select

    end function cross_product

end module symmetry
