module excit_gen_utils
use const
implicit none

!Routines for the power_pitzer/heat bath excit gens

contains

    subroutine select_ij_heat_bath(rng, nel, i_weights_precalc, ij_weights_precalc, cdet, i, j, i_ind, j_ind, i_weights_occ, &
            i_weights_occ_tot, ij_weights_occ, ij_weights_occ_tot, ji_weights_occ, ji_weights_occ_tot, allowed_excitation)
        ! Routine to select i and j according to the heat bath algorithm. Used by heat_bath_uniform, heat_bath_single,
        ! power_pitzer_orderM_ij

        ! In:
        !   nel: number of electrons (= sys%nel)
        !   i_weights_precalc: precalculated weights for i
        !   ij_weights_precalc: precalculated weights for j given i
        !   cdet: current determinant to attempt spawning from.
        ! In/Out:
        !   rng: random number generator
        ! Out:
        !   allowed_excitation: true if excitation with ij is possible.
        !   i_weights_occ: weights of i for all occupied spinorbitals.
        !   ij_weights_occ: weights of j for all occupied spinorbitals, given i.
        !   ji_weights_occ: weights of i for all occupied spinorbitals, given j (reverse selection for pgen calculation).
        !   i_weights_occ_tot: sum of weights of i for all occupied spinorbitals.
        !   ij_weights_occ_tot: sum of weights of j for all occupied spinorbitals, given i.
        !   ji_weights_occ_tot: sum of weights of i for all occupied spinorbitals, given j.

        use determinants, only: det_info_t
        use dSFMT_interface, only: dSFMT_t
        use alias, only: select_weighted_value

        integer, intent(in) :: nel
        real(p), intent(in) :: i_weights_precalc(:), ij_weights_precalc(:,:)
        type(det_info_t), intent(in) :: cdet
        type(dSFMT_t), intent(inout) :: rng
        real(p), intent(out) :: i_weights_occ(:), ij_weights_occ(:), ji_weights_occ(:)
        real(p), intent(out) :: i_weights_occ_tot, ij_weights_occ_tot, ji_weights_occ_tot
        logical, intent(out) :: allowed_excitation
        
        integer :: pos_occ, i_ind, j_ind, i, j

        i_weights_occ_tot = 0.0_p
        do pos_occ = 1, nel
            i_weights_occ(pos_occ) = i_weights_precalc(cdet%occ_list(pos_occ))
            i_weights_occ_tot = i_weights_occ_tot + i_weights_occ(pos_occ)
         end do
                
        i_ind = select_weighted_value(rng, nel, i_weights_occ, i_weights_occ_tot)
        i = cdet%occ_list(i_ind)

        ij_weights_occ_tot = 0.0_p
        do pos_occ = 1, nel
            ij_weights_occ(pos_occ) = ij_weights_precalc(cdet%occ_list(pos_occ),i)
            ij_weights_occ_tot = ij_weights_occ_tot + ij_weights_occ(pos_occ)
        end do

        if (ij_weights_occ_tot > 0.0_p) then
            ! There is a j for this i.
            j_ind = select_weighted_value(rng, nel, ij_weights_occ, ij_weights_occ_tot)
            j = cdet%occ_list(j_ind)

            ! Pre-compute the other direction (first selecting j then i) as well as that is required for pgen.
            ji_weights_occ_tot = 0.0_p
            do pos_occ = 1, nel
                ji_weights_occ(pos_occ) = ij_weights_precalc(cdet%occ_list(pos_occ),j)
                ji_weights_occ_tot = ji_weights_occ_tot + ji_weights_occ(pos_occ)
            end do
            allowed_excitation = .true.
        else
            allowed_excitation = .false.
        end if

    end subroutine select_ij_heat_bath

    subroutine init_double_weights_ab(sys, i, j, weight)
        ! WARNING: this routine assumes that i /= j!
        ! Routine that helps set up weights in a heat bath manner for the part where it loops over a and b.

        ! In:
        !   sys: system information
        !   i,j: orbitals i and j. i/=j.
        ! In/Out:
        !   weight: Hijab summed over a and b in this function. Can be an ongoing sum over i and j as well.

        use system, only: sys_t
        use read_in_symmetry, only: cross_product_basis_read_in
        use proc_pointers, only: slater_condon2_excit_ptr, abs_hmatel_ptr
        use hamiltonian_data, only: hmatel_t

        type(sys_t), intent(in) :: sys
        integer, intent(in) :: i, j
        real(p), intent(inout) :: weight

        integer :: ij_sym, isymb, i_tmp, j_tmp, a, b, a_tmp, b_tmp
        type(hmatel_t) :: hmatel

        if (j < i) then
            i_tmp = j
            j_tmp = i
        else
            i_tmp = i
            j_tmp = j
        end if 
                    
        ! The symmetry of b (=b_cdet), isymb, is given by
        ! (sym_i_cdet* x sym_j_cdet* x sym_a_cdet)* = sym_b_cdet
        ! (at least for Abelian point groups)
        ! ij_sym: symmetry conjugate of the irreducible representation spanned by the codensity
        !        \phi_i_cdet*\phi_j_cdet. (We assume that ij is going to be in the bra of the excitation.)
        ! [todo] - Check whether order of i and j matters here.

        ij_sym = sys%read_in%sym_conj_ptr(sys%read_in, cross_product_basis_read_in(sys, i_tmp, j_tmp))
        
        !$omp parallel do default(none) &
        !$omp shared(sys,i,j,i_tmp,j_tmp,ij_sym,slater_condon2_excit_ptr,abs_hmatel_ptr) &
        !$omp private(a,b,a_tmp,b_tmp,isymb,hmatel) reduction(+:weight)
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
                        weight = weight + abs_hmatel_ptr(hmatel)
                    end if
                end do
            end if
        end do
        !$omp end parallel do

    end subroutine init_double_weights_ab
end module excit_gen_utils
