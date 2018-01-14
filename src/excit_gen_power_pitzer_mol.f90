module excit_gen_power_pitzer_mol

! A module containing excitations generators for molecules which weight excitations according to the exchange matrix elements.

use const, only: i0, p, depsilon

implicit none

! [review] - JSS: some code-style uniformity please.  e.g. end do/end if instead of end do and end if

contains

    subroutine init_excit_mol_power_pitzer_occ_ref(sys, ref, pp)

        ! Generate excitation tables from the reference for the
        ! gen_excit_mol_power_pitzer_occ_ref excitation generator.
        ! This creates a random excitation from a det and calculates both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Power-Pitzer bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>), see J.D. Power, R.M. Pitzer, Chem. Phys. Lett.,
        ! 478-483 (1974).
        ! This is an O(M) version which pretends the determinant excited from is the reference,
        ! then modifies the selected orbitals to be those of the determinant given.
        ! Each occupied and virtual not present in the det we're actually given will be
        ! mapped to the one of the equivalent free numerical index in the reference.

        ! In:
        !    sys: system object being studied.
        !    ref: the reference from which we are exciting.
        ! In/Out:
        !    pp: an empty excit_gen_power_pitzer_t object which gets filled with
        !           the alias tables required to generate excitations.

        use system, only: sys_t
        use qmc_data, only: reference_t
        use sort, only: qsort
        use proc_pointers, only: create_weighted_excitation_list_ptr
        use excit_gens, only: excit_gen_power_pitzer_t
        use alias, only: generate_alias_tables
        type(sys_t), intent(in) :: sys
        type(reference_t), intent(in) :: ref
        type(excit_gen_power_pitzer_t), intent(inout) :: pp

        integer :: i, j, ind_a, ind_b, maxv, nv, bsym
        
        ! Temp storage
        maxv = max(sys%nvirt_alpha,sys%nvirt_beta)
        allocate(pp%ia_aliasU(maxv,sys%nel))
        allocate(pp%ia_aliasK(maxv,sys%nel))
        allocate(pp%ia_weights(maxv,sys%nel))
        allocate(pp%ia_weights_tot(sys%nel))
        allocate(pp%jb_aliasU(maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%nel))
        allocate(pp%jb_aliasK(maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%nel))
        allocate(pp%jb_weights(maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%nel))
        allocate(pp%jb_weights_tot(sys%sym0_tot:sys%sym_max_tot, sys%nel))
        allocate(pp%occ_list(sys%nel + 1))  ! The +1 is a pad to allow loops to look better
        allocate(pp%virt_list_alpha(sys%nvirt_alpha))
        allocate(pp%virt_list_beta(sys%nvirt_beta))
        
        pp%occ_list(:sys%nel) = ref%occ_list0(:sys%nel)
        pp%occ_list(sys%nel + 1) = sys%basis%nbasis*2  ! A pad
        ! [todo] - Consider testing j <= sys%nel below instead of having this pad.
        
        ! Now sort this, just in case we have an old restart file and the reference was not sorted then.
        call qsort(pp%occ_list,sys%nel)

        ! Make the unocc list.
        j = 1     ! The next occ to look at
        ind_a = 0 ! The present position in the virt_list we're making
        ind_b = 0 ! The present position in the virt_list we're making
        
        do i = 1, sys%basis%nbasis
            if (i==pp%occ_list(j)) then ! Our basis fn is in the ref
                ! Due to the +1 pad in occ_list, there is not danger of going past array boundaries here.
                j = j + 1
            else ! Need to store it as a virt
                if (sys%basis%basis_fns(i)%Ms == -1) then ! beta
                    ind_b = ind_b + 1
                    pp%virt_list_beta(ind_b) = i
                else
                    ind_a = ind_a + 1
                    pp%virt_list_alpha(ind_a) = i
                end if
            end if
        end do

        ! pp%virt_list_*(:) now contains the lists of virtual alpha and beta with respect to ref.

        ! Now generate the occ->virtual weighting lists and alias tables.
        do i = 1, sys%nel
            j = pp%occ_list(i)  ! The elec we're looking at
            if (sys%basis%basis_fns(j)%Ms == -1) then ! beta
                nv = sys%nvirt_beta
                if (nv > 0) then
                    call create_weighted_excitation_list_ptr(sys, j, 0, pp%virt_list_beta, nv, pp%ia_weights(:,i), &
                                                            pp%ia_weights_tot(i))
                    call check_min_weight_ratio(pp%ia_weights(:,i), pp%ia_weights_tot(i), nv, pp%power_pitzer_min_weight)
                    call generate_alias_tables(nv, pp%ia_weights(:,i), pp%ia_weights_tot(i), pp%ia_aliasU(:,i), &
                                               pp%ia_aliasK(:,i))
                end if
                do bsym = sys%sym0_tot, sys%sym_max_tot
                    if (sys%read_in%pg_sym%nbasis_sym_spin(1,bsym) > 0) then
                        call create_weighted_excitation_list_ptr(sys, j, 0, sys%read_in%pg_sym%sym_spin_basis_fns(:,1,bsym), &
                            sys%read_in%pg_sym%nbasis_sym_spin(1,bsym), pp%jb_weights(:,bsym,i), pp%jb_weights_tot(bsym,i))
                        call check_min_weight_ratio(pp%jb_weights(:,bsym,i), pp%jb_weights_tot(bsym,i), &
                                                   sys%read_in%pg_sym%nbasis_sym_spin(1,bsym), pp%power_pitzer_min_weight)
                        call generate_alias_tables(sys%read_in%pg_sym%nbasis_sym_spin(1,bsym), pp%jb_weights(:,bsym,i), &
                            pp%jb_weights_tot(bsym,i), pp%jb_aliasU(:,bsym,i), pp%jb_aliasK(:,bsym,i))
                    end if
                end do
            else ! alpha
                nv = sys%nvirt_alpha
                if (nv > 0) then
                    call create_weighted_excitation_list_ptr(sys, j, 0, pp%virt_list_alpha, nv, pp%ia_weights(:,i), &
                                                             pp%ia_weights_tot(i))
                    call check_min_weight_ratio(pp%ia_weights(:,i), pp%ia_weights_tot(i), nv, pp%power_pitzer_min_weight)
                    call generate_alias_tables(nv, pp%ia_weights(:,i), pp%ia_weights_tot(i), pp%ia_aliasU(:,i), &
                                               pp%ia_aliasK(:,i))
                end if
                do bsym = sys%sym0_tot, sys%sym_max_tot
                    if (sys%read_in%pg_sym%nbasis_sym_spin(2,bsym) > 0) then
                        call create_weighted_excitation_list_ptr(sys, j, 0, sys%read_in%pg_sym%sym_spin_basis_fns(:,2,bsym), &
                            sys%read_in%pg_sym%nbasis_sym_spin(2,bsym), pp%jb_weights(:,bsym,i), pp%jb_weights_tot(bsym,i))
                        call check_min_weight_ratio(pp%jb_weights(:,bsym,i), pp%jb_weights_tot(bsym,i), &
                                                   sys%read_in%pg_sym%nbasis_sym_spin(2,bsym), pp%power_pitzer_min_weight)
                        call generate_alias_tables(sys%read_in%pg_sym%nbasis_sym_spin(2,bsym), pp%jb_weights(:,bsym,i), &
                            pp%jb_weights_tot(bsym,i), pp%jb_aliasU(:,bsym,i), pp%jb_aliasK(:,bsym,i))
                    end if
                end do
            end if
        end do
    end subroutine init_excit_mol_power_pitzer_occ_ref

    subroutine check_min_weight_ratio(weights, weights_tot, weights_len, min_ratio)
        
        ! Restrict the minimum ratio of weights(i)/weights_tot to be min_ratio/number of orbitals. Of course, as the total
        ! weight weights_tot gets updated, some weights set earlier might then fall below the min_ratio again.

        ! In:
        !   weights_len: number of elements in weights list
        !   min_ratio: minimum value of weights(i)/weights_tot
        ! In/Out:
        !   weights: list of weights
        !   weights_tot: sum of weights
    
        use const, only: depsilon

        integer :: weights_len
        real(p), intent(in) :: min_ratio
        real(p), intent(inout) :: weights(:), weights_tot

        integer :: i, j, k, min_weights_counter, non_zero_weights_len
        real(p) :: weights_keep, min_weight, min_weight_tmp

        min_weight_tmp = 0.0_p
        non_zero_weights_len = 0

        if ((weights_tot > 0.0_p) .and. (min_ratio > 0.0_p)) then
            
            ! Find the number of non zero weights.
            do i = 1, weights_len
                if (weights(i) > 0.0_p) then
                    non_zero_weights_len = non_zero_weights_len + 1
                end if
            end do

            min_weight = (min_ratio/real(non_zero_weights_len)) * weights_tot

            ! Find the correct min_weight such that min_ratio*weights_tot/non_zero_weights_len is min_weight at the end.            
            do while (abs(min_weight_tmp - min_weight) > depsilon)
                min_weight_tmp = min_weight
                weights_keep = 0.0_p
                min_weights_counter = 0
                
                do k = 1, weights_len
                    if ((weights(k) > 0.0_p) .and. (weights(k) < min_weight)) then
                        min_weights_counter = min_weights_counter + 1
                    else
                        weights_keep = weights_keep + weights(k)
                    end if            
                end do
                if (min_weights_counter == non_zero_weights_len) then
                    exit
                end if
                ! The weights_tot of the next (future) iteration is calculated as
                ! weights_tot (next iteration) = weights_keep + 
                ! min_ratio*min_weights_counter*weights_tot (next iteration) /non_zero_weights_len,
                ! which is then solved to be 
                ! weights_tot (next iteration) = weights_keep / (1-min_ratio*min_weights_counter/non_zero_weights_len).
                ! Substitute into min_weight = weights_tot * min_ratio/non_zero_weights_len
                ! and get the expression below.
                min_weight = (min_ratio/real(non_zero_weights_len)) * &
                    (weights_keep/(1-(min_ratio*real(min_weights_counter)/real(non_zero_weights_len))))
            end do

            ! Set the new weights if required and update weights_tot.
            weights_tot = 0.0_p
            do j = 1, weights_len
                if ((weights(j) > 0.0_p) .and. (weights(j) < min_weight)) then
                    weights(j) = min_weight
                end if
                weights_tot = weights_tot + weights(j)
            end do
                
        end if

    end subroutine check_min_weight_ratio
 
    subroutine init_excit_mol_power_pitzer_orderN(sys, ref, pp)

        ! Generate excitation tables for all spinorbitals for the gen_excit_mol_power_pitzer
        ! excitation generator.

        ! In:
        !    sys: system object being studied.
        !    ref: the reference from which we are exciting.
        ! In/Out:
        !    pp: an empty excit_gen_power_pitzer_t object which gets filled with
        !           the alias tables required to generate excitations.

        use system, only: sys_t
        use qmc_data, only: reference_t
        use sort, only: qsort
        use proc_pointers, only: create_weighted_excitation_list_ptr, slater_condon2_excit_ptr
        use proc_pointers, only: abs_hmatel_ptr, single_excitation_weight_ptr
        use excit_gens, only: excit_gen_power_pitzer_t
        use alias, only: generate_alias_tables
        use read_in_symmetry, only: cross_product_basis_read_in
        use hamiltonian_data, only: hmatel_t
        type(sys_t), intent(in) :: sys
        type(reference_t), intent(in) :: ref
        type(excit_gen_power_pitzer_t), intent(inout) :: pp
        type(hmatel_t) :: hmatel

        integer :: i, j, a, b, ind_a, ind_b, ind_virt, ind_a_virt, ind_b_virt, maxv, nv, bsym, ij_sym, isyma, isymb, ims, imsa
        integer :: i_tmp, j_tmp, a_tmp, b_tmp, nall
        real(p) :: i_weight, ij_weight
        
        ! Temp storage
        allocate(pp%i_all_aliasU(sys%nel))
        allocate(pp%i_all_aliasK(sys%nel))
        allocate(pp%i_all_weights(sys%nel))
        ! allocate(pp%i_all_weights_tot)
        allocate(pp%i_single_aliasU(sys%nel))
        allocate(pp%i_single_aliasK(sys%nel))
        allocate(pp%i_single_weights(sys%nel))
        ! allocate(pp%i_single_weights_tot)
        allocate(pp%ij_all_aliasU(sys%nel,sys%basis%nbasis))
        allocate(pp%ij_all_aliasK(sys%nel,sys%basis%nbasis))
        allocate(pp%ij_all_weights(sys%nel,sys%basis%nbasis))
        allocate(pp%ij_all_weights_tot(sys%basis%nbasis))
        allocate(pp%ia_all_weights_tot(sys%basis%nbasis)) 
        allocate(pp%ia_single_weights_tot(sys%basis%nbasis))
        allocate(pp%ia_single_aliasU(maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%basis%nbasis))
        allocate(pp%ia_single_aliasK(maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%basis%nbasis))
        allocate(pp%ia_single_weights(maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%basis%nbasis))
        allocate(pp%jb_all_aliasU(maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis))
        allocate(pp%jb_all_aliasK(maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis))
        allocate(pp%jb_all_weights(maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis))
        allocate(pp%jb_all_weights_tot(sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis))
        allocate(pp%occ_list(sys%nel + 1))  ! The +1 is a pad to allow loops to look better
        allocate(pp%all_list_alpha(sys%basis%nbasis))
        allocate(pp%all_list_beta(sys%basis%nbasis))

        pp%occ_list(:sys%nel) = ref%occ_list0(:sys%nel)
        pp%occ_list(sys%nel + 1) = sys%basis%nbasis*2  ! A pad
        ! [todo] - Consider testing j <= sys%nel below instead of having this pad.

        ! Now sort this, just in case we have an old restart file and the reference was not sorted then.
        call qsort(pp%occ_list,sys%nel)

        ! Fill the list with alpha and the list with betas.
        ind_a = 0
        ind_b = 0
        ind_virt = 0
        ind_a_virt = 0
        ind_b_virt = 0
        j = 1

        do i = 1, sys%basis%nbasis
            if (sys%basis%basis_fns(i)%Ms == -1) then ! beta
                ind_b = ind_b + 1
                pp%all_list_beta(ind_b) = i
            else
                ind_a = ind_a + 1
                pp%all_list_alpha(ind_a) = i
            end if
        end do

        pp%n_all_alpha = ind_a
        pp%n_all_beta = ind_b

        allocate(pp%ia_all_aliasU(max(pp%n_all_alpha,pp%n_all_beta),sys%basis%nbasis))
        allocate(pp%ia_all_aliasK(max(pp%n_all_alpha,pp%n_all_beta),sys%basis%nbasis))
        allocate(pp%ia_all_weights(max(pp%n_all_alpha,pp%n_all_beta),sys%basis%nbasis))

        ! Now set up weight tables.
        ! Single Excitations.
        pp%i_single_weights_tot = 0.0_p
        do i = 1, sys%nel
            i_weight = 0.0_p
            ims = sys%basis%basis_fns(pp%occ_list(i))%ms
            isyma = sys%read_in%cross_product_sym_ptr(sys%read_in, sys%basis%basis_fns(pp%occ_list(i))%sym, &
                                                    sys%read_in%pg_sym%gamma_sym)
            do a = 1, sys%basis%nbasis
            ! Check that a is not i and has the required spin and symmetry.
                if ((a /= pp%occ_list(i)) .and. (sys%basis%basis_fns(a)%sym == isyma) .and. &
                    (sys%basis%basis_fns(a)%ms == ims)) then
                    i_weight = i_weight + single_excitation_weight_ptr(sys, ref, pp%occ_list(i), a)
                end if
            end do
            if (i_weight < depsilon) then
                ! because we map i later, even if i->a is not allowed/ has been wrongly assigned a zero weight,
                ! it needs a weight
                ! [todo] - a bit arbitrary. maybe make bigger?
                i_weight = 0.00001_p/real(sys%nel)
            end if
            pp%i_single_weights(i) = i_weight
            pp%i_single_weights_tot = pp%i_single_weights_tot + i_weight
        end do
        
        call generate_alias_tables(sys%nel, pp%i_single_weights(:), pp%i_single_weights_tot, pp%i_single_aliasU(:), &
                                pp%i_single_aliasK(:))

        do i = 1, sys%basis%nbasis
            pp%ia_single_weights_tot(i) = 0.0_p
            ims = sys%basis%basis_fns(i)%ms
            ! Convert ims which is in {-1, +1} notation to imsa which is {1, 2}.
            imsa = (3 + ims)/2
            isyma = sys%read_in%cross_product_sym_ptr(sys%read_in, sys%basis%basis_fns(i)%sym, sys%read_in%pg_sym%gamma_sym)
            do a = 1, sys%read_in%pg_sym%nbasis_sym_spin(imsa,isyma)
                pp%ia_single_weights(a, i) = 0.0_p
                if (sys%read_in%pg_sym%sym_spin_basis_fns(a,imsa, isyma) /= i) then
                    pp%ia_single_weights(a, i) = single_excitation_weight_ptr(sys, ref, i, &
                        sys%read_in%pg_sym%sym_spin_basis_fns(a,imsa,isyma))
                    if (pp%ia_single_weights(a, i) < depsilon) then
! [review] - AJWT: This hard-coded 0.01 is a bit arbitrary.
                        ! i-> a spin and symmetry allowed but weight assigned zero. fix this.
                        ! [todo] - really?
                        ! [todo] - need to cast with precision p?
                        ! [todo] - is this the best weight? a bit arbitrary.
                        pp%ia_single_weights(a, i) = 0.01_p/real(sys%read_in%pg_sym%nbasis_sym_spin(imsa,isyma))
                    end if
                end if
                pp%ia_single_weights_tot(i) = pp%ia_single_weights_tot(i) + pp%ia_single_weights(a, i)
            end do
            call generate_alias_tables(sys%read_in%pg_sym%nbasis_sym_spin(imsa,isyma), pp%ia_single_weights(:,i), &
                                    pp%ia_single_weights_tot(i), pp%ia_single_aliasU(:,i), pp%ia_single_aliasK(:,i))
        end do

        ! Double Excitations.
        ! Generate the i weighting lists and alias tables for possible (spin conserved - symmetry cannot be checked due to latter
        ! mapping which only conserves spin) double excitations.
        ! i and j are drawn from spinorbitals occupied in the reference and a and b can be all orbitals. i!=j and a!=b.
        ! i and j can equal a and b because we later map i. Single excitations are not considered. [todo]
        pp%i_all_weights_tot = 0.0_p
        do i = 1, sys%nel
            i_weight = 0.0_p
            do j = 1, sys%nel
                if (i /= j) then
                    if (pp%occ_list(j) < pp%occ_list(i)) then
                        i_tmp = pp%occ_list(j)
                        j_tmp = pp%occ_list(i)
                    else
                        i_tmp = pp%occ_list(i)
                        j_tmp = pp%occ_list(j)
                    end if
                    ! The symmetry of b (=b_cdet), isymb, is given by
                    ! (sym_i_cdet* x sym_j_cdet* x sym_a_cdet)* = sym_b_cdet
                    ! (at least for Abelian point groups)
                    ! ij_sym: symmetry conjugate of the irreducible representation spanned by the codensity
                    !        \phi_i_cdet*\phi_j_cdet. (We assume that ij is going to be in the bra of the excitation.)
                    ! [todo] - Check whether order of i and j matters here.
                    ij_sym = sys%read_in%sym_conj_ptr(sys%read_in, cross_product_basis_read_in(sys, i_tmp, j_tmp))
                    do a = 1, sys%basis%nbasis
                        if ((a /= i_tmp) .and. (a /= j_tmp)) then
                            isymb = sys%read_in%sym_conj_ptr(sys%read_in, &
                                        sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, sys%basis%basis_fns(a)%sym))
                            do b = 1, sys%basis%nbasis
                                ! Check spin conservation and symmetry conservation.
                                if ((((sys%basis%basis_fns(i_tmp)%Ms == sys%basis%basis_fns(a)%Ms) .and. &
                                    (sys%basis%basis_fns(j_tmp)%Ms == sys%basis%basis_fns(b)%Ms)) .or. &
                                    ((sys%basis%basis_fns(i_tmp)%Ms == sys%basis%basis_fns(b)%Ms) .and. &
                                    (sys%basis%basis_fns(j_tmp)%Ms == sys%basis%basis_fns(a)%Ms))) .and. &
                                    (sys%basis%basis_fns(b)%sym == isymb) .and. (b /= a) .and. (b /= i_tmp) .and. &
                                    (b/=j_tmp)) then
                                    if (b < a) then
                                        a_tmp = b
                                        b_tmp = a
                                    else
                                        a_tmp = a
                                        b_tmp = b
                                    end if
                                    ! slater_condon2_excit does not check whether ij -> ab is allowed but have
                                    ! checked for that, so it is ok.
                                    hmatel = slater_condon2_excit_ptr(sys, i_tmp, j_tmp, a_tmp, b_tmp, .false.)
                                    i_weight = i_weight + abs_hmatel_ptr(hmatel)
                                end if
                            end do
                        end if 
                    end do
                end if
            end do
            if (i_weight < depsilon) then
                ! [todo] - think of better min weight (needed because after mapping i might be a valid orbital to use)
! [review] - AJWT: Need at least some reasoning behind this.
                i_weight = 0.00001_p/real(sys%nel)
            end if
            pp%i_all_weights(i) = i_weight
            pp%i_all_weights_tot = pp%i_all_weights_tot + i_weight
        end do

        call generate_alias_tables(sys%nel, pp%i_all_weights(:), pp%i_all_weights_tot, pp%i_all_aliasU(:), pp%i_all_aliasK(:))

        ! Generate the j given i weighting lists and alias tables. a and b cannot equal i (they are drawn from the same set).
        ! [todo] - Does this work if orbitals are frozen?
! [review] - AJWT: nbasis should know the number of available orbitals, so I don't see why this shouldn't work for systems with freezing.
        do i = 1, sys%basis%nbasis
            pp%ij_all_weights_tot(i) = 0.0_p
            do j = 1, sys%nel
                ij_weight = 0.0_p
                if (pp%occ_list(j) /= i) then
                    ! Make sure i and j are ordered.
                    if (pp%occ_list(j) < i) then
                        i_tmp = pp%occ_list(j)
                        j_tmp = i
                    else
                        i_tmp = i
                        j_tmp = pp%occ_list(j)
                    end if
                    ij_sym = sys%read_in%sym_conj_ptr(sys%read_in, cross_product_basis_read_in(sys, i_tmp, j_tmp))
                    do a = 1, sys%basis%nbasis
                        if ((a /= i_tmp) .and. (a /= j_tmp)) then
                            isymb = sys%read_in%sym_conj_ptr(sys%read_in, &
                                    sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, sys%basis%basis_fns(a)%sym))
                            do b = 1, sys%basis%nbasis 
                                if ((((sys%basis%basis_fns(i_tmp)%Ms == sys%basis%basis_fns(a)%Ms) .and. &
                                    (sys%basis%basis_fns(j_tmp)%Ms == sys%basis%basis_fns(b)%Ms)) .or. &
                                    ((sys%basis%basis_fns(i_tmp)%Ms == sys%basis%basis_fns(b)%Ms) .and. &
                                    (sys%basis%basis_fns(j_tmp)%Ms == sys%basis%basis_fns(a)%Ms))) .and. &
                                    (sys%basis%basis_fns(b)%sym == isymb) .and. (a /= b) .and. (b /= i_tmp) .and. &
                                    (b /= j_tmp)) then
                                    if (b < a) then
                                        a_tmp = b
                                        b_tmp = a
                                    else
                                        a_tmp = a
                                        b_tmp = b
                                    end if
                                    ! slater_condon2 does not check whether ij -> ab is allowed by symmetry/spin
                                    ! but we have checked for that here so it is ok.
                                    hmatel = slater_condon2_excit_ptr(sys, i_tmp, j_tmp, a_tmp, b_tmp, .false.)
                                    ij_weight = ij_weight + abs_hmatel_ptr(hmatel)
                                end if
                            end do
                        end if
                    end do
                    if (ij_weight < depsilon) then
! [review] - AJWT: rationale behind this.
                        ! [todo] - think of better min weight (needed because after mapping i might be a valid orbital to use)
                        ij_weight = 0.00001_p/real(sys%nel)
                    end if
                else
                    ! i == pp%occ_list(j) which means i_cdet == j_ref here but that does not mean that i_cdet == j_cdet.
                    ! Assign a uniform weight.
                    ij_weight = 1.0_p/sys%nel
                end if
                pp%ij_all_weights(j,i) = ij_weight
                pp%ij_all_weights_tot(i) = pp%ij_all_weights_tot(i) + ij_weight
            end do
            call generate_alias_tables(sys%nel, pp%ij_all_weights(:,i), pp%ij_all_weights_tot(i), pp%ij_all_aliasU(:,i), &
                                    pp%ij_all_aliasK(:,i))
        end do

        ! Now generate the occ->virtual weighting lists and alias tables.
        ! This breaks in the case where there is only one spinorbital in the system with a certain spin. This is unlikely
        ! and will be ignored. [todo] - check for case where sys%nbeta and sys%nalpha are 1?
        ! [todo] - do we need min weights here? probably not because we do not map and if <ai|ia> = 0 that is probably deserved?
        do i = 1, sys%basis%nbasis
            if (sys%basis%basis_fns(i)%Ms == -1) then ! beta
                nall = pp%n_all_beta
                if (nall > 0) then
                    call create_weighted_excitation_list_ptr(sys, i, i, pp%all_list_beta, nall, pp%ia_all_weights(:,i), &
                                                            pp%ia_all_weights_tot(i))
                    call generate_alias_tables(nall, pp%ia_all_weights(:,i), pp%ia_all_weights_tot(i), pp%ia_all_aliasU(:,i), &
                                               pp%ia_all_aliasK(:,i))
                end if
                do bsym = sys%sym0_tot, sys%sym_max_tot
                    if (sys%read_in%pg_sym%nbasis_sym_spin(1,bsym) > 0) then
                        call create_weighted_excitation_list_ptr(sys, i, i, sys%read_in%pg_sym%sym_spin_basis_fns(:,1,bsym), &
                            sys%read_in%pg_sym%nbasis_sym_spin(1,bsym), pp%jb_all_weights(:,bsym,i), pp%jb_all_weights_tot(bsym,i))
                        call generate_alias_tables(sys%read_in%pg_sym%nbasis_sym_spin(1,bsym), pp%jb_all_weights(:,bsym,i), &
                            pp%jb_all_weights_tot(bsym,i), pp%jb_all_aliasU(:,bsym,i), pp%jb_all_aliasK(:,bsym,i))
                    end if
                end do
            else ! alpha
                nall = pp%n_all_alpha
                if (nall > 0) then
                    call create_weighted_excitation_list_ptr(sys, i, i, pp%all_list_alpha, nall, pp%ia_all_weights(:,i), &
                                                             pp%ia_all_weights_tot(i))

                    call generate_alias_tables(nall, pp%ia_all_weights(:,i), pp%ia_all_weights_tot(i), pp%ia_all_aliasU(:,i), &
                                               pp%ia_all_aliasK(:,i))
                end if
                do bsym = sys%sym0_tot, sys%sym_max_tot
                    if (sys%read_in%pg_sym%nbasis_sym_spin(2,bsym) > 0) then
                        call create_weighted_excitation_list_ptr(sys, i, i, sys%read_in%pg_sym%sym_spin_basis_fns(:,2,bsym), &
                            sys%read_in%pg_sym%nbasis_sym_spin(2,bsym), pp%jb_all_weights(:,bsym,i), pp%jb_all_weights_tot(bsym,i))
                        call generate_alias_tables(sys%read_in%pg_sym%nbasis_sym_spin(2,bsym), pp%jb_all_weights(:,bsym,i), &
                            pp%jb_all_weights_tot(bsym,i), pp%jb_all_aliasU(:,bsym,i), pp%jb_all_aliasK(:,bsym,i))
                    end if
                end do
            end if
        end do

    end subroutine init_excit_mol_power_pitzer_orderN

    subroutine gen_excit_mol_power_pitzer_occ_ref(rng, sys, excit_gen_data, cdet, pgen, connection, hmatel, allowed_excitation)

        ! Create a random excitation from cdet and calculate both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Power-Pitzer bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>), see J.D. Power, R.M. Pitzer, Chem. Phys. Lett.,
        ! 478-483 (1974).
        ! This is an O(M/64) version which pretends the determinant excited from is the reference,
        ! then modifies the selected orbitals to be those of the determinant given.
        ! Each occupied and virtual not present in the det we're actually given will be
        ! mapped to the one of the equivalent free numerical index in the reference.

        ! In:
        !    sys: system object being studied.
        !    excit_gen_data: Excitation generation data.
        !    cdet: info on the current determinant (cdet) that we will gen
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are gened.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant in molecular systems.
        !    allowed_excitation: false if a valid symmetry allowed excitation was not generated

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use excitations, only: find_excitation_permutation2,get_excitation_locations
        use proc_pointers, only: slater_condon2_excit_ptr
        use system, only: sys_t
        use excit_gen_mol, only: gen_single_excit_mol_no_renorm, choose_ij_mol
        use excit_gens, only: excit_gen_power_pitzer_t, excit_gen_data_t
        use alias, only: select_weighted_value_precalc
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use hamiltonian_data, only: hmatel_t
        use read_in_symmetry, only: cross_product_basis_read_in
        use search, only: binary_search

        type(sys_t), intent(in) :: sys
        type(excit_gen_data_t), intent(in) :: excit_gen_data
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen
        type(hmatel_t), intent(out) :: hmatel
        type(excit_t), intent(out) :: connection
        logical, intent(out) :: allowed_excitation


        integer ::  ij_spin, ij_sym, i_ref_j_ref_sym, imsb, isyma, isymb
        
        ! We distinguish here between a_ref and a_cdet. a_ref is a in the world where the reference is fully occupied
        ! and we excite from the reference. We then map a_ref onto a_cdet which is a in the world where cdet is fully
        ! occupied (which is the world we are actually in). This mapping is a one-to-one mapping.

        ! a_ind_ref is the index of a in the world where the reference is fully occupied, etc.

        ! a_ind_rev_cdet is the index of a_cdet if a had been chosen after b (relevant when both have the same spin
        ! and the reverse selection has to be considered).
        
        integer :: i_ind_ref, j_ind_ref, a_ind_ref, b_ind_cdet
        integer :: a_ind_rev_cdet, b_ind_rev_ref
        integer :: i_ref, j_ref, a_ref, b_ref, i_cdet, j_cdet, a_cdet, b_cdet

        integer :: nex
        integer :: cdet_store(sys%nel)
        integer :: ref_store(sys%nel)
        integer :: ii, jj, t
        real(p) :: pgen_ij

        logical :: found, a_found

        ! 1. Select single or double.
        if (get_rand_close_open(rng) < excit_gen_data%pattempt_single) then

            call gen_single_excit_mol_no_renorm(rng, sys, excit_gen_data%pattempt_single, cdet, pgen, connection, hmatel, &
                                            allowed_excitation)

        else
            ! We have a double
            associate( pp => excit_gen_data%excit_gen_pp )

                ! 2b. Select orbitals to excite from
                
                call choose_ij_mol(rng, sys, pp%occ_list, i_ind_ref, j_ind_ref, i_ref, j_ref, i_ref_j_ref_sym, ij_spin, pgen_ij)

                ! At this point we pretend we're the reference, and fix up mapping ref's orbitals to cdet's orbitals later.
                i_ref = pp%occ_list(i_ind_ref)
                j_ref = pp%occ_list(j_ind_ref)

                ! We now need to select the orbitals to excite into which we do with weighting:
                ! p(ab|ij) = p(a|i) p(b|j) + p(a|j) p(b|i)
                ! We actually choose a|i then b|j, but since we could have also generated the excitation b from i and a from j, we
                ! need to include that prob too.

                ! Given i_ref, use the alias method to select a_ref with appropriate probability from the set of orbitals
                ! of the same spin as i_ref that are unoccupied if all electrons are in the reference.
                if (sys%basis%basis_fns(i_ref)%Ms < 0) then
                    if (sys%nvirt_beta > 0) then
                        a_ind_ref = select_weighted_value_precalc(rng, sys%nvirt_beta, pp%ia_aliasU(:,i_ind_ref), &
                                                               pp%ia_aliasK(:,i_ind_ref))
                        a_ref = pp%virt_list_beta(a_ind_ref)
                        a_found = .true.
                    else
                        a_found = .false.
                    end if
                else
                    if (sys%nvirt_alpha > 0) then
                        a_ind_ref = select_weighted_value_precalc(rng, sys%nvirt_alpha, pp%ia_aliasU(:,i_ind_ref), &
                                                               pp%ia_aliasK(:,i_ind_ref))
                        a_ref = pp%virt_list_alpha(a_ind_ref)
                        a_found = .true.
                    else
                        a_found = .false.
                    end if
                end if

                if (a_found) then
                    ! To conserve total spin, b and j will have the same spin, as a and i have the same spin.
                    ! To find what symmetry b should have, we first have to map i,j and a to what they correspond to
                    ! had we considered cdet and not the reference.
                
                    ! We need a list of the substitutions in cdet vs the ref.  i.e. for each orbital in the ref-lined-up
                    ! cdet which is not in ref, we need the location.
                    ! This is currently done with an O(N) step, but might be sped up at least.

                    call get_excitation_locations(pp%occ_list, cdet%occ_list, ref_store, cdet_store, sys%nel, nex)
                    ! These orbitals might not be aligned in the most efficient way:
                    !  They may not match in spin, so first deal with this

                    ! ref store (e.g.) contains the indices within pp%occ_list of the orbitals
                    ! which have been excited from.
                    ! [todo] - Consider having four lists separated by spin instead of two, i.e. ref_store_alpha and
                    ! [todo] - ref_store_beta instead of ref_store and the same for cdet_store.
                    ! [todo] - Consider calculating these lists once per determinants/excitor instead of once per excitation
                    ! [todo] - generator call.
                    do ii=1, nex
                        associate(bfns=>sys%basis%basis_fns)
                            if (bfns(pp%occ_list(ref_store(ii)))%Ms /= bfns(cdet%occ_list(cdet_store(ii)))%Ms) then
                                jj = ii + 1
                                do while (bfns(pp%occ_list(ref_store(ii)))%Ms /= bfns(cdet%occ_list(cdet_store(jj)))%Ms)
                                    jj = jj + 1
                                end do
                                ! det's jj now points to an orb of the same spin as ref's ii, so swap cdet_store's ii and jj.
                                t = cdet_store(ii)
                                cdet_store(ii) = cdet_store(jj)
                                cdet_store(jj) = t
                            end if
                        end associate
                    end do
                
                    ! Now see if i_ref and j_ref are in ref_store or a_ref in cdet_store and map appropriately
                    i_cdet = i_ref
                    j_cdet = j_ref
                    a_cdet = a_ref
                    ! ref_store  contains the indices within pp%occ_list of the orbitals which are excited out of ref into cdet
                    ! cdet_store  contains the indices within cdet%occ_list of the orbitals which are in cdet (excited out
                    ! of ref).  i_ind_ref and j_ind_ref are the indices of the orbitals in pp%occ_list which we're exciting from.
                    do ii=1, nex
                        if (ref_store(ii) == i_ind_ref) then  ! i_ref isn't actually in cdet, so we assign i_cdet to the orb that is
                            i_cdet = cdet%occ_list(cdet_store(ii))
                        else if (ref_store(ii) == j_ind_ref) then ! j_ref isn't actually in cdet, so we assign j_cdet to the orb that is
                            j_cdet = cdet%occ_list(cdet_store(ii))
                        end if
                        if (cdet%occ_list(cdet_store(ii)) == a_ref) then
                            a_cdet = pp%occ_list(ref_store(ii)) ! a_ref is occupied in cdet, assign a_cdet to the orb that is not
                        end if
                    end do

                    ! The symmetry of b (=b_cdet), isymb, is given by
                    ! (sym_i_cdet* x sym_j_cdet* x sym_a_cdet)* = sym_b_cdet
                    ! (at least for Abelian point groups)
                    ! ij_sym: symmetry conjugate of the irreducible representation spanned by the codensity
                    !        \phi_i_cdet*\phi_j_cdet. (We assume that ij is going to be in the bra of the excitation.)
                    ij_sym = sys%read_in%sym_conj_ptr(sys%read_in, cross_product_basis_read_in(sys, i_cdet, j_cdet))

                    isymb = sys%read_in%sym_conj_ptr(sys%read_in, &
                                sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, sys%basis%basis_fns(a_cdet)%sym))
                    ! Ms_i + Ms_j = Ms_a + Ms_b => Ms_b = Ms_i + Ms_j - Ms_a.
                    ! Given that Ms_a = Ms_i, Ms_b = Ms_j.
                    ! Ms_k is +1 if up and -1 if down but imsb is +2 if up and +1 if down,
                    ! therefore a conversion is necessary.
                    imsb = (sys%basis%basis_fns(j_ref)%Ms + 3)/2
                end if

                ! Check whether an orbital (occupied or not) with required spin and symmetry exists.
                if (a_found .and. (sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb) > 0)) then
                    ! Using alias tables based on the reference, find b_cdet out of the set of (all) orbitals that have
                    ! the required spin and symmetry. Note that these orbitals might be occupied in the reference and/or
                    ! cdet (although we only care about whether they are occupied in cdet which we deal with later).

                    b_ind_cdet = select_weighted_value_precalc(rng, sys%read_in%pg_sym%nbasis_sym_spin(imsb, isymb), &
                                        pp%jb_aliasU(:, isymb, j_ind_ref), pp%jb_aliasK(:, isymb, j_ind_ref))
                    b_cdet = sys%read_in%pg_sym%sym_spin_basis_fns(b_ind_cdet, imsb, isymb)

                    ! Check that a_cdet /= b_cdet and that b_cdet is not occupied in cdet:
                    if (a_cdet /= b_cdet .and. .not.btest(cdet%f(sys%basis%bit_lookup(2,b_cdet)), &
                        sys%basis%bit_lookup(1,b_cdet))) then
                        
                        ! 3b. Probability of generating this excitation.

                        ! Calculate p(ab|ij) = p(a|i) p(j|b) + p(b|i)p(a|j)
                        if (ij_spin == 0) then
                            ! Not possible to have chosen the reversed excitation.
                            pgen = pp%ia_weights(a_ind_ref, i_ind_ref) / pp%ia_weights_tot(i_ind_ref) &
                                    * pp%jb_weights(b_ind_cdet, isymb, j_ind_ref) / pp%jb_weights_tot(isymb, j_ind_ref)
                        else
                            ! i and j have same spin, so could have been selected in the other order.
                            ! Need to find b_ref, the orbital b would have been in the world where we focus on the reference.
                            b_ref = b_cdet

                            do ii=1, nex
                                if (pp%occ_list(ref_store(ii)) == b_cdet) then
                                    ! b_cdet is occupied in ref, assign b_ref to the orb that is not
                                    b_ref = cdet%occ_list(cdet_store(ii))
                                    exit
                                end if
                            end do

                            if (imsb == 1) then
                                ! find index b as if we had it selected first and as a from list of unoccupied virtual orbitals.
                                call binary_search(pp%virt_list_beta, b_ref, 1, sys%nvirt_beta, found, b_ind_rev_ref)
                            else
                                call binary_search(pp%virt_list_alpha, b_ref, 1, sys%nvirt_alpha, found, b_ind_rev_ref)
                            end if
                            isyma = sys%read_in%sym_conj_ptr(sys%read_in, &
                                        sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, isymb))
                            ! imsa = imsb
                            call binary_search(sys%read_in%pg_sym%sym_spin_basis_fns(:,imsb,isyma), a_cdet, 1, &
                                    sys%read_in%pg_sym%nbasis_sym_spin(imsb,isyma), found, a_ind_rev_cdet)

                            pgen = pp%ia_weights(a_ind_ref, i_ind_ref) / pp%ia_weights_tot(i_ind_ref) &
                                    * pp%jb_weights(b_ind_cdet, isymb, j_ind_ref) / pp%jb_weights_tot(isymb, j_ind_ref) &
                                +  pp%ia_weights(b_ind_rev_ref, i_ind_ref) / pp%ia_weights_tot(i_ind_ref) &
                                    * pp%jb_weights(a_ind_rev_cdet, isyma, j_ind_ref) / pp%jb_weights_tot(isyma, j_ind_ref)
                        end if

                        pgen = excit_gen_data%pattempt_double * pgen * pgen_ij ! pgen(ab)
                        connection%nexcit = 2
                        allowed_excitation = .true.
                    else
                        allowed_excitation = .false.
                    end if
                else
                    allowed_excitation = .false.
                end if

                if (allowed_excitation) then

                    if (i_cdet<j_cdet) then
                        connection%from_orb(1) = i_cdet
                        connection%from_orb(2) = j_cdet
                    else
                        connection%from_orb(2) = i_cdet
                        connection%from_orb(1) = j_cdet
                    end if
                    if (a_cdet<b_cdet) then
                        connection%to_orb(1) = a_cdet
                        connection%to_orb(2) = b_cdet
                    else
                        connection%to_orb(2) = a_cdet
                        connection%to_orb(1) = b_cdet
                    end if

                    ! 4b. Parity of permutation required to line up determinants.
                    ! NOTE: connection%from_orb and connection%to_orb *must* be ordered.
                    call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

                    ! 5b. Find the connecting matrix element.
                    hmatel = slater_condon2_excit_ptr(sys, connection%from_orb(1), connection%from_orb(2), &
                                                      connection%to_orb(1), connection%to_orb(2), connection%perm)
                else
                    ! Carelessly selected ij with no possible excitations.  Such
                    ! events are not worth the cost of renormalising the generation
                    ! probabilities.
                    ! Return a null excitation.
                    hmatel%c = cmplx(0.0_p, 0.0_p, p)
                    hmatel%r = 0.0_p
                    pgen = 1.0_p
                end if
            end associate
        end if

    end subroutine gen_excit_mol_power_pitzer_occ_ref

    subroutine gen_excit_mol_power_pitzer_orderN(rng, sys, excit_gen_data, cdet, pgen, connection, hmatel, allowed_excitation)

        ! Create a random excitation from cdet and calculate both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Power-Pitzer bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>), see J.D. Power, R.M. Pitzer, Chem. Phys. Lett.,
        ! 478-483 (1974).

! [review] - AJWT: Meaning...
        ! [todo] - more

        ! In:
        !    sys: system object being studied.
        !    excit_gen_data: Excitation generation data.
        !    cdet: info on the current determinant (cdet) that we will gen
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are gened.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant in molecular systems.
        !    allowed_excitation: false if a valid symmetry allowed excitation was not generated

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use excitations, only: find_excitation_permutation1, find_excitation_permutation2, get_excitation_locations
        use proc_pointers, only: slater_condon1_excit_ptr, slater_condon2_excit_ptr
        use system, only: sys_t
        use excit_gens, only: excit_gen_power_pitzer_t, excit_gen_data_t
        use alias, only: select_weighted_value_precalc
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use hamiltonian_data, only: hmatel_t
        use read_in_symmetry, only: cross_product_basis_read_in
        use search, only: binary_search

        type(sys_t), intent(in) :: sys
        type(excit_gen_data_t), intent(in) :: excit_gen_data
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen
        type(hmatel_t), intent(out) :: hmatel
        type(excit_t), intent(out) :: connection
        logical, intent(out) :: allowed_excitation


        integer ::  ij_spin, ij_sym, imsa, imsb, isyma, isymb
        
        ! We distinguish here between a_ref and a_cdet. a_ref is a in the world where the reference is fully occupied
        ! and we excite from the reference. We then map a_ref onto a_cdet which is a in the world where cdet is fully
        ! occupied (which is the world we are actually in). This mapping is a one-to-one mapping.

        ! a_ind_ref is the index of a in the world where the reference is fully occupied, etc.

        ! a_ind_rev_cdet is the index of a_cdet if a had been chosen after b (relevant when both have the same spin
        ! and the reverse selection has to be considered).
        
        integer :: i_ind_ref, j_ind_ref, a_ind_cdet, b_ind_cdet
        integer :: a_ind_rev_cdet, b_ind_rev_cdet
        integer :: i_ref, j_ref, i_cdet, j_cdet, a_cdet, b_cdet, j_cdet_tmp

        integer :: nex
        integer :: cdet_store(sys%nel)
        integer :: ref_store(sys%nel)
        integer :: ii, jj, t

        logical :: found

        ! 1. Select single or double.
        if (get_rand_close_open(rng) < excit_gen_data%pattempt_single) then  
            ! We have a single
            associate( pp => excit_gen_data%excit_gen_pp )
                ! 2b. Select orbitals to excite from
                
                i_ind_ref = select_weighted_value_precalc(rng, sys%nel, pp%i_single_aliasU(:), pp%i_single_aliasK(:))
                i_ref = pp%occ_list(i_ind_ref)
                
                ! Now map i_ref to i_cdet.
                call get_excitation_locations(pp%occ_list, cdet%occ_list, ref_store, cdet_store, sys%nel, nex)
                ! These orbitals might not be aligned in the most efficient way:
                !  They may not match in spin, so first deal with this

                ! ref store (e.g.) contains the indices within pp%occ_list of the orbitals
                ! which have been excited from.
                ! [todo] - Consider having four lists separated by spin instead of two, i.e. ref_store_alpha and
                ! [todo] - ref_store_beta instead of ref_store and the same for cdet_store.
                ! [todo] - Consider calculating these lists once per determinants/excitor instead of once per excitation
                ! [todo] - generator call.
                do ii=1, nex
                    associate(bfns=>sys%basis%basis_fns)
                        if (bfns(pp%occ_list(ref_store(ii)))%Ms /= bfns(cdet%occ_list(cdet_store(ii)))%Ms) then
                            jj = ii + 1
                            do while (bfns(pp%occ_list(ref_store(ii)))%Ms /= bfns(cdet%occ_list(cdet_store(jj)))%Ms)
                                jj = jj + 1
                            end do
                            ! det's jj now points to an orb of the same spin as ref's ii, so swap cdet_store's ii and jj.
                            t = cdet_store(ii)
                            cdet_store(ii) = cdet_store(jj)
                            cdet_store(jj) = t
                        end if
                    end associate
                end do
                ! Now see if i_ref is in ref_store and map appropriately
                i_cdet = i_ref
                ! ref_store  contains the indices within pp%occ_list of the orbitals which are excited out of ref into cdet
                ! cdet_store  contains the indices within cdet%occ_list of the orbitals which are in cdet (excited out
                ! of ref).  i_ind_ref is the index of the orbital in pp%occ_list which we're exciting from.
                do ii=1, nex
                    if (ref_store(ii) == i_ind_ref) then  ! i_ref isn't actually in cdet, so we assign i_cdet to the orb that is
                        i_cdet = cdet%occ_list(cdet_store(ii))
                        exit
                    end if
                end do
    
                ! Convert ims which is in {-1, +1} notation to imsa which is {1, 2}.
                imsa = (3 + sys%basis%basis_fns(i_cdet)%ms)/2
                isyma = sys%read_in%cross_product_sym_ptr(sys%read_in, sys%basis%basis_fns(i_cdet)%sym, &
                                                        sys%read_in%pg_sym%gamma_sym)
                if (sys%read_in%pg_sym%nbasis_sym_spin(imsa,isyma) > 0) then
                    a_ind_cdet = select_weighted_value_precalc(rng, sys%read_in%pg_sym%nbasis_sym_spin(imsa,isyma), &
                                                    pp%ia_single_aliasU(:, i_cdet), pp%ia_single_aliasK(:, i_cdet))
                    a_cdet = sys%read_in%pg_sym%sym_spin_basis_fns(a_ind_cdet, imsa, isyma)
                    if (.not. btest(cdet%f(sys%basis%bit_lookup(2,a_cdet)), sys%basis%bit_lookup(1,a_cdet))) then
                        allowed_excitation = .true.
                    else
                        allowed_excitation = .false.
                    end if
                else
                    allowed_excitation = .false.
                end if

                if (allowed_excitation) then
                    pgen = (pp%i_single_weights(i_ind_ref)/pp%i_single_weights_tot) * &
                            (pp%ia_single_weights(a_ind_cdet, i_cdet)/pp%ia_single_weights_tot(i_cdet))
                    pgen = excit_gen_data%pattempt_single * pgen ! pgen(ab)
                    connection%nexcit = 1
                    connection%to_orb(1) = a_cdet
                    connection%from_orb(1) = i_cdet
                    call find_excitation_permutation1(sys%basis%excit_mask, cdet%f, connection)
                    hmatel = slater_condon1_excit_ptr(sys, cdet%occ_list, connection%from_orb(1), &
                                          connection%to_orb(1), connection%perm)
                else
                    ! We have not found a valid excitation i -> a.  Such
                    ! events are not worth the cost of renormalising the generation
                    ! probabilities.
                    ! Return a null excitation.
                    hmatel%c = cmplx(0.0_p, 0.0_p, p)
                    hmatel%r = 0.0_p
                    pgen = 1.0_p
                end if

            end associate

        else
            ! We have a double
            associate( pp => excit_gen_data%excit_gen_pp )
                ! 2b. Select orbitals to excite from
                
                i_ind_ref = select_weighted_value_precalc(rng, sys%nel, pp%i_all_aliasU(:), pp%i_all_aliasK(:))
                i_ref = pp%occ_list(i_ind_ref)
                
                ! Now map i_ref to i_cdet.
                call get_excitation_locations(pp%occ_list, cdet%occ_list, ref_store, cdet_store, sys%nel, nex)
                ! These orbitals might not be aligned in the most efficient way:
                !  They may not match in spin, so first deal with this

                ! ref store (e.g.) contains the indices within pp%occ_list of the orbitals
                ! which have been excited from.
                ! [todo] - Consider having four lists separated by spin instead of two, i.e. ref_store_alpha and
                ! [todo] - ref_store_beta instead of ref_store and the same for cdet_store.
                ! [todo] - Consider calculating these lists once per determinants/excitor instead of once per excitation
                ! [todo] - generator call.
                do ii=1, nex
                    associate(bfns=>sys%basis%basis_fns)
                        if (bfns(pp%occ_list(ref_store(ii)))%Ms /= bfns(cdet%occ_list(cdet_store(ii)))%Ms) then
                            jj = ii + 1
                            do while (bfns(pp%occ_list(ref_store(ii)))%Ms /= bfns(cdet%occ_list(cdet_store(jj)))%Ms)
                                jj = jj + 1
                            end do
                            ! det's jj now points to an orb of the same spin as ref's ii, so swap cdet_store's ii and jj.
                            t = cdet_store(ii)
                            cdet_store(ii) = cdet_store(jj)
                            cdet_store(jj) = t
                        end if
                    end associate
                end do
                ! Now see if i_ref is in ref_store and map appropriately
                i_cdet = i_ref
                ! ref_store  contains the indices within pp%occ_list of the orbitals which are excited out of ref into cdet
                ! cdet_store  contains the indices within cdet%occ_list of the orbitals which are in cdet (excited out
                ! of ref).  i_ind_ref is the index of the orbital in pp%occ_list which we're exciting from.
                do ii=1, nex
                    if (ref_store(ii) == i_ind_ref) then  ! i_ref isn't actually in cdet, so we assign i_cdet to the orb that is
                        i_cdet = cdet%occ_list(cdet_store(ii))
                        exit
                    end if
                end do
                
                ! j is chosen from set of occupied spinorbitals in reference but with weights calculated for i_cdet.
                j_ind_ref = select_weighted_value_precalc(rng, sys%nel, pp%ij_all_aliasU(:,i_cdet), pp%ij_all_aliasK(:,i_cdet))
                j_ref = pp%occ_list(j_ind_ref)

                j_cdet = j_ref
                do ii=1, nex
                    if (ref_store(ii) == j_ind_ref) then  ! j_ref isn't actually in cdet, so we assign j_cdet to the orb that is
                        j_cdet = cdet%occ_list(cdet_store(ii))
                        exit
                    end if
                end do
                if (j_cdet /= i_cdet) then
                    allowed_excitation = .true. ! for now - that can change.
                    pgen = (pp%i_all_weights(i_ind_ref) / pp%i_all_weights_tot) * &
                            (pp%ij_all_weights(j_ind_ref,i_cdet) / pp%ij_all_weights_tot(i_cdet))
                    ij_spin = sys%basis%basis_fns(i_cdet)%Ms + sys%basis%basis_fns(j_cdet)%Ms
                    ! Could have selected i and j the other way around. 
                    pgen = pgen + ((pp%i_all_weights(j_ind_ref) / pp%i_all_weights_tot) * &
                            (pp%ij_all_weights(i_ind_ref,j_cdet) / pp%ij_all_weights_tot(j_cdet)))
                    ! Order i and j such that i<j.
                    if (j_cdet < i_cdet) then
                        j_cdet_tmp = j_cdet
                        j_cdet = i_cdet
                        i_cdet = j_cdet_tmp
                    end if
                else
                    allowed_excitation = .false.
                end if
                if (allowed_excitation) then
                    ! We now need to select the orbitals to excite into which we do with weighting:
                    ! p(ab|ij) = p(a|i) p(b|j) + p(a|j) p(b|i).
                    ! We actually choose a|i then b|j, but since we could have also generated the excitation b from i and a from j, we
                    ! need to include that too if they have the same spin.

                    ! Given i_cdet, use the alias method to select a_cdet with appropriate probability from the set of orbitals
                    ! of the same spin as i_cdet.
                    if (sys%basis%basis_fns(i_cdet)%Ms < 0) then
                        a_ind_cdet = select_weighted_value_precalc(rng, pp%n_all_beta, pp%ia_all_aliasU(:,i_cdet), &
                                                               pp%ia_all_aliasK(:,i_cdet))
                        a_cdet = pp%all_list_beta(a_ind_cdet)
                    else
                        a_ind_cdet = select_weighted_value_precalc(rng, pp%n_all_alpha, pp%ia_all_aliasU(:,i_cdet), &
                                                               pp%ia_all_aliasK(:,i_cdet))
                        a_cdet = pp%all_list_alpha(a_ind_cdet)
                    end if
                    ! Make sure a_cdet is a virtual orbital (not occupied in c_det).
                    if (btest(cdet%f(sys%basis%bit_lookup(2,a_cdet)), sys%basis%bit_lookup(1,a_cdet))) then
                        allowed_excitation = .false.
                    end if
                end if
                if (allowed_excitation) then
                    ! To conserve total spin, b and j will have the same spin, as a and i have the same spin.

                    ! The symmetry of b (=b_cdet), isymb, is given by
                    ! (sym_i_cdet* x sym_j_cdet* x sym_a_cdet)* = sym_b_cdet
                    ! (at least for Abelian point groups)
                    ! ij_sym: symmetry conjugate of the irreducible representation spanned by the codensity
                    !        \phi_i_cdet*\phi_j_cdet. (We assume that ij is going to be in the bra of the excitation.)
                    ij_sym = sys%read_in%sym_conj_ptr(sys%read_in, cross_product_basis_read_in(sys, i_cdet, j_cdet))

                    isymb = sys%read_in%sym_conj_ptr(sys%read_in, &
                                sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, sys%basis%basis_fns(a_cdet)%sym))
                    ! Ms_i + Ms_j = Ms_a + Ms_b => Ms_b = Ms_i + Ms_j - Ms_a.
                    ! Given that Ms_a = Ms_i, Ms_b = Ms_j.
                    ! Ms_k is +1 if up and -1 if down but imsb is +2 if up and +1 if down,
                    ! therefore a conversion is necessary.
                    imsb = (sys%basis%basis_fns(j_cdet)%Ms + 3)/2

                    if (sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb) == 0) then
                        allowed_excitation = .false.
                    end if
                end if
                ! Check whether an orbital (occupied or not) with required spin and symmetry exists.
                if (allowed_excitation) then
                    ! Find b_cdet out of the set of (all) orbitals that have the required spin and symmetry for given j_cdet. 
                    ! Note that these orbitals might be occupied.
                    b_ind_cdet = select_weighted_value_precalc(rng, sys%read_in%pg_sym%nbasis_sym_spin(imsb, isymb), &
                                        pp%jb_all_aliasU(:, isymb, j_cdet), pp%jb_all_aliasK(:, isymb, j_cdet))
                    b_cdet = sys%read_in%pg_sym%sym_spin_basis_fns(b_ind_cdet, imsb, isymb)

                    ! Check that a_cdet /= b_cdet and that b_cdet is not occupied in cdet:
                    if ((a_cdet /= b_cdet) .and. .not. btest(cdet%f(sys%basis%bit_lookup(2,b_cdet)), &
                        sys%basis%bit_lookup(1,b_cdet))) then
                        
                        ! 3b. Probability of generating this excitation.

                        ! Calculate p(ab|ij) = p(a|i) p(j|b) + p(b|i)p(a|j)
                        if (ij_spin == 0) then
                            ! Not possible to have chosen the reversed excitation.
                            pgen = pgen * (pp%ia_all_weights(a_ind_cdet, i_cdet) / pp%ia_all_weights_tot(i_cdet) &
                                    * pp%jb_all_weights(b_ind_cdet, isymb, j_cdet) / pp%jb_all_weights_tot(isymb, j_cdet))
                        else
                            ! i and j have same spin, so could have been selected in the other order.

                            if (imsb == 1) then
                                ! find index b as if we had it selected first and as a from list of beta orbitals.
                                call binary_search(pp%all_list_beta, b_cdet, 1, pp%n_all_beta, found, b_ind_rev_cdet)
                            else
                                call binary_search(pp%all_list_alpha, b_cdet, 1, pp%n_all_alpha, found, b_ind_rev_cdet)
                            end if
                            isyma = sys%read_in%sym_conj_ptr(sys%read_in, &
                                        sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, isymb))
                            ! imsa = imsb
                            call binary_search(sys%read_in%pg_sym%sym_spin_basis_fns(:,imsb,isyma), a_cdet, 1, &
                                    sys%read_in%pg_sym%nbasis_sym_spin(imsb,isyma), found, a_ind_rev_cdet)

                            pgen = pgen * (pp%ia_all_weights(a_ind_cdet, i_cdet) / pp%ia_all_weights_tot(i_cdet) &
                                    * pp%jb_all_weights(b_ind_cdet, isymb, j_cdet) / pp%jb_all_weights_tot(isymb, j_cdet) &
                                +  pp%ia_all_weights(b_ind_rev_cdet, i_cdet) / pp%ia_all_weights_tot(i_cdet) &
                                    * pp%jb_all_weights(a_ind_rev_cdet, isyma, j_cdet) / pp%jb_all_weights_tot(isyma, j_cdet))
                        end if

                        pgen = excit_gen_data%pattempt_double * pgen ! pgen(ab)
                        connection%nexcit = 2
                    else
                        allowed_excitation = .false.
                    end if
                end if


                if (allowed_excitation) then
                    ! i and j are ordered.
                    connection%from_orb(1) = i_cdet
                    connection%from_orb(2) = j_cdet
                    if (a_cdet<b_cdet) then
                        connection%to_orb(1) = a_cdet
                        connection%to_orb(2) = b_cdet
                    else
                        connection%to_orb(2) = a_cdet
                        connection%to_orb(1) = b_cdet
                    end if
                    ! 4b. Parity of permutation required to line up determinants.
                    ! NOTE: connection%from_orb and connection%to_orb *must* be ordered.
                    call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

                    ! 5b. Find the connecting matrix element.
                    hmatel = slater_condon2_excit_ptr(sys, connection%from_orb(1), connection%from_orb(2), &
                                                      connection%to_orb(1), connection%to_orb(2), connection%perm)
                else
                    ! We have not found a valid excitation ij -> ab.  Such
                    ! events are not worth the cost of renormalising the generation
                    ! probabilities.
                    ! Return a null excitation.
                    hmatel%c = cmplx(0.0_p, 0.0_p, p)
                    hmatel%r = 0.0_p
                    pgen = 1.0_p
                end if
            end associate
        end if

    end subroutine gen_excit_mol_power_pitzer_orderN

    subroutine gen_excit_mol_power_pitzer_occ(rng, sys, excit_gen_data, cdet, pgen, connection, hmatel, allowed_excitation)

        ! Create a random excitation from cdet and calculate both the probability
        ! of selecting that excitation and the Hamiltonian matrix element.
        ! Weight the double excitations according the the Power-Pitzer bound
        ! <ij|ab> <= Sqrt(<ia|ai><jb|bj>), see J.D. Power, R.M. Pitzer, Chem. Phys. Lett.,
        ! 478-483 (1974).
        ! This requires a lookup of O(M) two-electron integrals in its setup.

        ! In:
        !    sys: system object being studied.
        !    excit_gen_data: Excitation generation data.
        !    cdet: info on the current determinant (cdet) that we will gen
        !        from.
        !    parent_sign: sign of the population on the parent determinant (i.e.
        !        either a positive or negative integer).
        ! In/Out:
        !    rng: random number generator.
        ! Out:
        !    pgen: probability of generating the excited determinant from cdet.
        !    connection: excitation connection between the current determinant
        !        and the child determinant, on which progeny are gened.
        !    hmatel: < D | H | D' >, the Hamiltonian matrix element between a
        !        determinant and a connected determinant in molecular systems.
        !    allowed_excitation: false if a valid symmetry allowed excitation was not generated

        use determinants, only: det_info_t
        use excitations, only: excit_t
        use excitations, only: find_excitation_permutation2
        use proc_pointers, only: slater_condon2_excit_ptr, create_weighted_excitation_list_ptr
        use system, only: sys_t
        use excit_gen_mol, only: gen_single_excit_mol_no_renorm, choose_ij_mol
        use hamiltonian_data, only: hmatel_t
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use search, only: binary_search
        use checking, only: check_allocate, check_deallocate
        use excit_gens, only: excit_gen_power_pitzer_t, excit_gen_data_t
        use alias, only: select_weighted_value

        type(sys_t), intent(in) :: sys
        type(excit_gen_data_t), intent(in) :: excit_gen_data
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: pgen
        type(hmatel_t), intent(out) :: hmatel
        type(excit_t), intent(out) :: connection
        logical, intent(out) :: allowed_excitation

        integer ::  ij_spin, ij_sym, ierr
        logical :: found, a_found
        real(p), allocatable :: ia_weights(:), ja_weights(:), jb_weights(:)
        real(p) :: ia_weights_tot, ja_weights_tot, jb_weights_tot
        real(p) :: pgen_ij
        integer :: a, b, i, j, a_ind, b_ind, a_ind_rev, b_ind_rev, i_ind, j_ind, isymb, imsb, isyma

        ! 1. Select single or double.
        if (get_rand_close_open(rng) < excit_gen_data%pattempt_single) then

            call gen_single_excit_mol_no_renorm(rng, sys, excit_gen_data%pattempt_single, cdet, pgen, connection, hmatel, &
                                            allowed_excitation)

        else
            ! We have a double

            ! 2b. Select orbitals to excite from
            
            call choose_ij_mol(rng, sys, cdet%occ_list, i_ind, j_ind, i, j, ij_sym, ij_spin, pgen_ij)

            ! Now we've chosen i and j.
 
            ! We now need to select the orbitals to excite into which we do with weighting:
            ! p(ab|ij) = p(a|i) p(b|j) + p(a|j) p(b|i)
            
            ! We actually choose a|i then b|j, but since we could have also generated the excitation b from i and a from j, we need to include that prob too.

            ! Given i, construct the weights of all possible a
            if (sys%basis%basis_fns(i)%Ms < 0) then
                ! [todo] - Consider doing a binary/linear search instead of using the alias method.
                if (sys%nvirt_beta > 0) then
                    allocate(ia_weights(1:sys%nvirt_beta), stat=ierr)
                    call check_allocate('ia_weights', sys%nvirt_beta, ierr)
                    call create_weighted_excitation_list_ptr(sys, i, 0, cdet%unocc_list_beta, sys%nvirt_beta, ia_weights, &
                                                             ia_weights_tot)
                    if (ia_weights_tot > 0.0_p) then
                        ! Use the alias method to select i with the appropriate probability
                        a_ind = select_weighted_value(rng, sys%nvirt_beta, ia_weights, ia_weights_tot)
                        a = cdet%unocc_list_beta(a_ind)
                        a_found = .true.
                    else
                        a_found = .false.
                    end if
                else
                    a_found = .false.
                end if
            else
                if (sys%nvirt_alpha > 0) then
                    allocate(ia_weights(1:sys%nvirt_alpha), stat=ierr)
                    call check_allocate('ia_weights', sys%nvirt_alpha, ierr)

                    call create_weighted_excitation_list_ptr(sys, i, 0, cdet%unocc_list_alpha, sys%nvirt_alpha, ia_weights, &
                                                             ia_weights_tot)
                    if (ia_weights_tot > 0.0_p) then
                        ! Use the alias method to select i with the appropriate probability
                        a_ind = select_weighted_value(rng, sys%nvirt_alpha, ia_weights, ia_weights_tot)
                        a = cdet%unocc_list_alpha(a_ind)
                        a_found = .true.
                    else
                        a_found = .false.
                    end if
                else
                    a_found = .false.
                end if
            end if

            if (a_found) then
                ! Given i,j,a construct the weights of all possible b
                ! This requires that total symmetry and spin are conserved.
                ! The symmetry of b (isymb) is given by
                ! (sym_i* x sym_j* x sym_a)* = sym_b
                ! (at least for Abelian point groups)
                isymb = sys%read_in%sym_conj_ptr(sys%read_in, &
                        sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, sys%basis%basis_fns(a)%sym))
                ! Ms_i + Ms_j = Ms_a + Ms_b => Ms_b = Ms_i + Ms_j - Ms_a
                ! Ms_k is +1 if up and -1 if down but imsb is +2 if up and +1 if down,
                ! therefore a conversion is necessary.
                imsb = (ij_spin - sys%basis%basis_fns(a)%Ms + 3)/2
            
                if (sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb) > 0) then
                    allocate(jb_weights(1:sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb)), stat=ierr)
                    call check_allocate('jb_weights', sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb), ierr)
                    call create_weighted_excitation_list_ptr(sys, j, a, sys%read_in%pg_sym%sym_spin_basis_fns(:,imsb,isymb), &
                                                             sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb), jb_weights, &
                                                             jb_weights_tot)
                else
                    jb_weights_tot = 0.0_p
                end if
            end if
            ! Test whether at least one possible b given i,j,a exists.
            ! Note that we did not need a btest for orbital a because we only considered
            ! virtual orbitals there.

            if (a_found .and. (jb_weights_tot > 0.0_p)) then
                ! Use the alias method to select b with the appropriate probability
                b_ind = select_weighted_value(rng, sys%read_in%pg_sym%nbasis_sym_spin(imsb,isymb), jb_weights, jb_weights_tot)
                b = sys%read_in%pg_sym%sym_spin_basis_fns(b_ind,imsb,isymb)

                if (.not.btest(cdet%f(sys%basis%bit_lookup(2,b)), sys%basis%bit_lookup(1,b))) then
         
                    ! 3b. Probability of generating this excitation.

                    ! Calculate p(ab|ij) = p(a|i) p(j|b) + p(b|i)p(a|j)
                    if (ij_spin==0) then
                        ! not possible to have chosen the reversed excitation
                        pgen=ia_weights(a_ind)/ia_weights_tot*jb_weights(b_ind)/jb_weights_tot
                    else
                        ! i and j have same spin, so could have been selected in the other order.
                        if (imsb == 1) then
                            ! find index b as if we had it selected first and as a from list of unoccupied virtual orbitals.
                            ! This uses the fact that the position of b in cdet%unocc_list_{beta,alpha} is the same
                            ! position index as in b's index in ia_weights is.
                            call binary_search(cdet%unocc_list_beta, b, 1, sys%nvirt_beta, found, b_ind_rev)
                        else
                            call binary_search(cdet%unocc_list_alpha, b, 1, sys%nvirt_alpha, found, b_ind_rev)
                        end if

                        isyma = sys%read_in%sym_conj_ptr(sys%read_in, &
                                sys%read_in%cross_product_sym_ptr(sys%read_in, ij_sym, isymb))
                        ! imsa = imsb
                        allocate(ja_weights(1:sys%read_in%pg_sym%nbasis_sym_spin(imsb,isyma)), stat=ierr)
                        call check_allocate('ja_weights', sys%read_in%pg_sym%nbasis_sym_spin(imsb,isyma), ierr)
                        call create_weighted_excitation_list_ptr(sys, j, b, sys%read_in%pg_sym%sym_spin_basis_fns(:,imsb,isyma),&
                                            sys%read_in%pg_sym%nbasis_sym_spin(imsb,isyma), ja_weights, ja_weights_tot)
                        call binary_search(sys%read_in%pg_sym%sym_spin_basis_fns(:,imsb,isyma), a, 1, &
                                    sys%read_in%pg_sym%nbasis_sym_spin(imsb,isyma), found, a_ind_rev)
                        pgen=       (ia_weights(a_ind)*jb_weights(b_ind)) / (ia_weights_tot*jb_weights_tot) + &
                            (ia_weights(b_ind_rev)*ja_weights(a_ind_rev) ) / (ia_weights_tot*ja_weights_tot)
                    end if
                    pgen = excit_gen_data%pattempt_double * pgen * pgen_ij ! pgen(ab)
                    connection%nexcit = 2

                    ! if create_weighted_excitation_list checks this then this check is redundant
                    ! allowed_excitation = a /= b

                    if (i<j) then
                        connection%from_orb(1) = i
                        connection%from_orb(2) = j
                    else
                        connection%from_orb(2) = i
                        connection%from_orb(1) = j
                    end if
                    if (a<b) then
                        connection%to_orb(1) = a
                        connection%to_orb(2) = b
                    else
                        connection%to_orb(2) = a
                        connection%to_orb(1) = b
                    end if
                    allowed_excitation = .true.
                else
                    allowed_excitation = .false.
                end if
            else
                allowed_excitation = .false.
            end if
           
            if (allowed_excitation) then

                ! 4b. Parity of permutation required to line up determinants.
                ! NOTE: connection%from_orb and connection%to_orb *must* be ordered.
                call find_excitation_permutation2(sys%basis%excit_mask, cdet%f, connection)

                ! 5b. Find the connecting matrix element.
                hmatel = slater_condon2_excit_ptr(sys, connection%from_orb(1), connection%from_orb(2), &
                                            connection%to_orb(1), connection%to_orb(2), connection%perm)
            else
                ! Carelessly selected ij with no possible excitations.  Such
                ! events are not worth the cost of renormalising the generation
                ! probabilities.
                ! Return a null excitation.
                hmatel%c = cmplx(0.0_p, 0.0_p, p)
                hmatel%r = 0.0_p
                pgen = 1.0_p
            end if

        end if

        ! deallocate weight arrays if allocated
        if (allocated(ia_weights)) deallocate(ia_weights)
        if (allocated(jb_weights)) deallocate(jb_weights)
        if (allocated(ja_weights)) deallocate(ja_weights)

    end subroutine gen_excit_mol_power_pitzer_occ

end module excit_gen_power_pitzer_mol
