module excit_gens
use const
implicit none

!Data for the power_pitzer excit gen

! The integer types have been chosen to be int_32
integer(int_32), parameter :: int_bas = int_32

type p_single_double_t
    ! collects data to update pattempt_single (and therefore pattempt_double) such that
    ! the means in the distribution of hmatel/pgen for singles and doubles are roughly equal.
    real(p) :: h_pgen_singles_sum = 0.0_p ! hmatel/pgen sum for singles
    real(p) :: h_pgen_doubles_sum = 0.0_p ! hamtel/pgen sum for doubles
    real(p) :: excit_gen_singles = 0.0_p ! number of valid singles excitations created
    real(p) :: excit_gen_doubles = 0.0_p ! number of valid doubles excitations created
    real(p) :: every_attempts = 1000000.0_p ! update pattempt_single every every_attempts a single or double ex. happened
    real(p) :: every_min_attempts = 10.0_p ! unless there were not more than every_min_attempts of single or double ex. since
    real(p) :: counter = 1.0_p
    logical :: vary_psingles = .false. ! still update pattempt_singles
end type p_single_double_t

! Type containing alias tables, etc, needed when using the power pitzer ("occ_ref") 
! excitation generator, that considers weights, etc, as seen from the reference.
type excit_gen_power_pitzer_t
    ! Minimum ratio over number of orbitals of individual weight/total weight. Aims to reduce p_gens that are too big.
    real(p) :: power_pitzer_min_weight
    ! ia_aliasU(:,i) stores the alias table of real U considering an excitation from i 
    ! to a virtual orbital of the same spin. 
    ! Lengths of array: (max(sys%nvirt_alpha,sys%nvirt_beta),sys%nel).  
    real(p), allocatable :: ia_aliasU(:,:) 
    ! ia_aliasK(:,i) stores the alias table of integer K considering an excitation from
    ! i to a virtual orbital of the same spin.
    ! Lengths of array: (max(sys%nvirt_alpha,sys%nvirt_beta),sys%nel) 
    integer(int_bas), allocatable :: ia_aliasK(:,:) 
    ! ia_weights(:,i) stores the weights considering an excitation from i to a virtual
    ! orbital of the same spin.
    ! Lengths of array: (max(sys%nvirt_alpha,sys%nvirt_beta),sys%nel)
    real(p), allocatable :: ia_weights(:,:) 
    ! ia_weights_tot(i) is the sum over j in ia_weights(j,i). 
    ! Length of array: (sys%nel)
    real(p), allocatable :: ia_weights_tot(:) 
    ! jb_aliasU(:,syma,i) stores the alias table of real U considering an excitation
    ! from i to any orbital (occupied or not) of same spin and symmetry syma.
    ! Lengths of array: (maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%sym0_tot:sys%sym_max_tot,sys%nel)
    real(p), allocatable :: jb_aliasU(:,:,:) 
    ! jb_aliasK(:,syma,i) stores the alias table of integer K considering an excitation
    ! from i to any orbital (occupied or not) of same spin and symmetry syma.
    ! Lengths of array: (maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%sym0_tot:sys%sym_max_tot,sys%nel)
    integer(int_bas), allocatable :: jb_aliasK(:,:,:) 
    ! jb_weights(:,syma,i) stores the weights considering an excitation from i to any
    ! orbital (occupied or not) of same spin and symmetry syma.
    ! Lengths of array: (maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%sym0_tot:sys%sym_max_tot,sys%nel)
    real(p), allocatable :: jb_weights(:,:,:) 
    ! jb_weights_tot(syma,i) is the sum over j in jb_weights(j,syma,i).
    ! Lengths of array: (sys%sym0_tot:sys%sym_max_tot,sys%nel)
    real(p), allocatable :: jb_weights_tot(:,:)
    ! virt_list_alpha is a list of all virtual alpha orbitals as seen from the reference.
    ! Length of array: (sys%nvirt_alpha)
    integer(int_bas), allocatable :: virt_list_alpha(:) 
    ! virt_list_beta is a list of all virtual beta orbitals as seen from the reference.
    ! Length of array: (sys%nvirt_beta)
    integer(int_bas), allocatable :: virt_list_beta(:) 
    ! occ_list(:) is the list of occupied orbitals in the reference.
    ! Length of array: (sys%nel+1) - The +1 is a pad.
    integer(int_bas), allocatable :: occ_list(:)
    ! Length of array: sys%nel
    real(p), allocatable :: i_all_aliasU(:)
    ! Length of array: sys%nel
    integer(int_bas), allocatable :: i_all_aliasK(:)
    ! Length of array: sys%nel
    real(p), allocatable :: i_all_weights(:)
    real(p) :: i_all_weights_tot
    ! Length of array: sys%nel
    real(p), allocatable :: i_single_aliasU(:)
    ! Length of array: sys%nel
    integer(int_bas), allocatable :: i_single_aliasK(:)
    ! Length of array: sys%nel
    real(p), allocatable :: i_single_weights(:)
    real(p) :: i_single_weights_tot
    ! Length of array: sys%nel,sys%basis%nbasis
    real(p), allocatable :: ij_all_aliasU(:,:)
    ! Length of array: sys%nel,sys%basis%nbasis
    integer(int_bas), allocatable :: ij_all_aliasK(:,:)
    ! Length of array: sys%nel,sys%basis%nbasis
    real(p), allocatable :: ij_all_weights(:,:)
    ! Length of array: sys%basis%nbasis
    real(p), allocatable :: ij_all_weights_tot(:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ia_all_aliasU(:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis
    integer(int_bas), allocatable :: ia_all_aliasK(:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ia_all_weights(:,:)
    ! Length of array: sys%basis%nbasis
    real(p), allocatable :: ia_all_weights_tot(:)
    ! Length of array: sys%basis%nbasis
    real(p), allocatable :: ia_single_weights_tot(:)
    ! Length of array: maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%basis%nbasis
    real(p), allocatable :: ia_single_aliasU(:,:)
    ! Length of array: maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%basis%nbasis
    integer(int_bas), allocatable :: ia_single_aliasK(:,:)
    ! Length of array: maxval(sys%read_in%pg_sym%nbasis_sym_spin),sys%basis%nbasis
    real(p), allocatable :: ia_single_weights(:,:)
    ! Length of array: maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis
    real(p), allocatable :: jb_all_aliasU(:,:,:)
    ! Length of array: maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis
    integer(int_bas), allocatable :: jb_all_aliasK(:,:,:)
    ! Length of array: maxval(sys%read_in%pg_sym%nbasis_sym_spin), sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis
    real(p), allocatable :: jb_all_weights(:,:,:)
    ! Length of array: sys%sym0_tot:sys%sym_max_tot, sys%basis%nbasis
    real(p), allocatable :: jb_all_weights_tot(:,:)
    ! Length of array: sys%basis%nbasis 
    integer(int_bas), allocatable :: all_list_alpha(:)
    ! Length of array: sys%basis%nbasis
    integer(int_bas), allocatable :: all_list_beta(:)
    ! Number of alpha spinorbitals
    integer(int_bas) :: n_all_alpha
    ! Number of beta spinorbitals
    integer(int_bas) :: n_all_beta

end type excit_gen_power_pitzer_t

type excit_gen_heat_bath_t
    ! Length of array: sys%basis%nbasis
    real(p), allocatable :: i_weights(:) ! This will hold S_p in the Holmes JCTC paper.
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ij_weights(:,:) ! This stores D_pq.
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ija_weights(:,:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ija_aliasU(:,:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    integer(int_bas), allocatable :: ija_aliasK(:,:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ija_weights_tot(:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ijab_weights(:,:,:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ijab_aliasU(:,:,:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    integer(int_bas), allocatable :: ijab_aliasK(:,:,:,:)
    ! Length of array: sys%basis%nbasis, sys%basis%nbasis, sys%basis%nbasis
    real(p), allocatable :: ijab_weights_tot(:,:,:)
    ! Length of array: sys%basis%nbasis,sys%basis%nbasis
    real(p), allocatable :: ia_weights(:,:)
end type excit_gen_heat_bath_t

!Type containing data for excitation generators
type excit_gen_data_t
    ! Excitation generator to use, duplicated from qmc_in.
    integer :: excit_gen

    ! Probability of attempting single or double excitations.
    real(p) :: pattempt_single, pattempt_double

    ! When creating an arbitrary excitation, k_i,k_j->k_a,k_b, we must conserve
    ! crystal momentum, k_i+k_j-k_a-k_b=0.  Hence once we've chosen k_i, k_j and
    ! k_a, k_b is uniquely defined.  Further, once we've chosen k_i and k_j and if
    ! we require k_b to exist in the basis, then only certain values of k_a are
    ! permitted.  sys%ueg%ternary_conserve(0,k1,k2,k3) gives how many k_a are permitted
    ! for k_i+k_j = (k1,k2,k3) and sys%ueg%ternary_conserve(1:,k1,k2,k3) gives a bit
    ! string with only bytes set corresponding to permitted k_a values.  Note only
    ! basis functions corresponding to *alpha* orbitals are set.
    ! For systems with dimensionality lower than 3, the higher ki values are set to
    ! 0, i.e. dimensions:
    ! (0:bit_string_len,-N:N,0,0) (1D)
    ! (0:bit_string_len,-N:N,-N:N,0) (2D)
    ! (0:bit_string_len,-N:N,-N:N,-N:N) (3D)
    ! NOTE: this contains values of k_i+k_j which cannot be formed by the basis with
    ! the energy cutoff.  Memory can be saved by not using a cubic array for
    ! k_i+k_j...
    integer(i0), allocatable :: ueg_ternary_conserve(:,:,:,:)
    type(excit_gen_power_pitzer_t) :: excit_gen_pp
    type(excit_gen_heat_bath_t) :: excit_gen_hb
    type (p_single_double_t) :: p_single_double
end type excit_gen_data_t

contains

    subroutine dealloc_excit_gen_data_t(excit_gen_data)

        ! Deallocate the excitation generator data.

        ! In/Out:
        !   excit_gen_data: excit_gen_data_t to be deallocated.

        ! It is a bit superfluous to have this subroutine for one deallocation, but it will be more
        ! useful in future.

        type(excit_gen_data_t), intent(inout) :: excit_gen_data

        if (allocated(excit_gen_data%ueg_ternary_conserve)) deallocate(excit_gen_data%ueg_ternary_conserve)

        call dealloc_excit_gen_power_pitzer_t(excit_gen_data%excit_gen_pp)
        call dealloc_excit_gen_heat_bath_t(excit_gen_data%excit_gen_hb)

    end subroutine dealloc_excit_gen_data_t

    subroutine dealloc_excit_gen_power_pitzer_t(excit_gen_pp)
        
        ! Deallocate the power pitzer excitation generator data.

        ! In/Out:
        !   excit_gen_pp: excit_gen_power_pitzer_t to be deallocated.

        type(excit_gen_power_pitzer_t), intent(inout) :: excit_gen_pp

        if (allocated(excit_gen_pp%ia_aliasU)) deallocate(excit_gen_pp%ia_aliasU)
        if (allocated(excit_gen_pp%ia_aliasK)) deallocate(excit_gen_pp%ia_aliasK)
        if (allocated(excit_gen_pp%ia_weights)) deallocate(excit_gen_pp%ia_weights)
        if (allocated(excit_gen_pp%ia_weights_tot)) deallocate(excit_gen_pp%ia_weights_tot)
        if (allocated(excit_gen_pp%jb_aliasU)) deallocate(excit_gen_pp%jb_aliasU)
        if (allocated(excit_gen_pp%jb_aliasK)) deallocate(excit_gen_pp%jb_aliasK)
        if (allocated(excit_gen_pp%jb_weights)) deallocate(excit_gen_pp%jb_weights)
        if (allocated(excit_gen_pp%jb_weights_tot)) deallocate(excit_gen_pp%jb_weights_tot)
        if (allocated(excit_gen_pp%virt_list_alpha)) deallocate(excit_gen_pp%virt_list_alpha)
        if (allocated(excit_gen_pp%virt_list_beta)) deallocate(excit_gen_pp%virt_list_beta)
        if (allocated(excit_gen_pp%occ_list)) deallocate(excit_gen_pp%occ_list)
        if (allocated(excit_gen_pp%i_all_aliasU)) deallocate(excit_gen_pp%i_all_aliasU)
        if (allocated(excit_gen_pp%i_all_aliasK)) deallocate(excit_gen_pp%i_all_aliasK)
        if (allocated(excit_gen_pp%i_all_weights)) deallocate(excit_gen_pp%i_all_weights)
        if (allocated(excit_gen_pp%i_single_aliasU)) deallocate(excit_gen_pp%i_single_aliasU)
        if (allocated(excit_gen_pp%i_single_aliasK)) deallocate(excit_gen_pp%i_single_aliasK)
        if (allocated(excit_gen_pp%i_single_weights)) deallocate(excit_gen_pp%i_single_weights)
        if (allocated(excit_gen_pp%ij_all_aliasU)) deallocate(excit_gen_pp%ij_all_aliasU)
        if (allocated(excit_gen_pp%ij_all_aliasK)) deallocate(excit_gen_pp%ij_all_aliasK)
        if (allocated(excit_gen_pp%ij_all_weights)) deallocate(excit_gen_pp%ij_all_weights)
        if (allocated(excit_gen_pp%ij_all_weights_tot)) deallocate(excit_gen_pp%ij_all_weights_tot)
        if (allocated(excit_gen_pp%ia_all_aliasU)) deallocate(excit_gen_pp%ia_all_aliasU)
        if (allocated(excit_gen_pp%ia_all_aliasK)) deallocate(excit_gen_pp%ia_all_aliasK)
        if (allocated(excit_gen_pp%ia_all_weights)) deallocate(excit_gen_pp%ia_all_weights)
        if (allocated(excit_gen_pp%ia_all_weights_tot)) deallocate(excit_gen_pp%ia_all_weights_tot)
        if (allocated(excit_gen_pp%ia_single_aliasU)) deallocate(excit_gen_pp%ia_single_aliasU)
        if (allocated(excit_gen_pp%ia_single_aliasK)) deallocate(excit_gen_pp%ia_single_aliasK)
        if (allocated(excit_gen_pp%ia_single_weights)) deallocate(excit_gen_pp%ia_single_weights)
        if (allocated(excit_gen_pp%ia_single_weights_tot)) deallocate(excit_gen_pp%ia_single_weights_tot)
        if (allocated(excit_gen_pp%jb_all_aliasU)) deallocate(excit_gen_pp%jb_all_aliasU)
        if (allocated(excit_gen_pp%jb_all_aliasK)) deallocate(excit_gen_pp%jb_all_aliasK)
        if (allocated(excit_gen_pp%jb_all_weights)) deallocate(excit_gen_pp%jb_all_weights)
        if (allocated(excit_gen_pp%jb_all_weights_tot)) deallocate(excit_gen_pp%jb_all_weights_tot)
        if (allocated(excit_gen_pp%all_list_alpha)) deallocate(excit_gen_pp%all_list_alpha)
        if (allocated(excit_gen_pp%all_list_beta)) deallocate(excit_gen_pp%all_list_beta)

    end subroutine dealloc_excit_gen_power_pitzer_t

    subroutine dealloc_excit_gen_heat_bath_t(excit_gen_hb)

        ! Deallocate the heat bath excitation generator data.

        ! In/Out:
        !   excit_gen_hb: excit_gen_heat_bath_t to be deallocated.

        type(excit_gen_heat_bath_t), intent(inout) :: excit_gen_hb

        if (allocated(excit_gen_hb%i_weights)) deallocate(excit_gen_hb%i_weights)
        if (allocated(excit_gen_hb%ij_weights)) deallocate(excit_gen_hb%ij_weights)
        if (allocated(excit_gen_hb%ija_weights)) deallocate(excit_gen_hb%ija_weights)
        if (allocated(excit_gen_hb%ija_aliasU)) deallocate(excit_gen_hb%ija_aliasU)
        if (allocated(excit_gen_hb%ija_aliasK)) deallocate(excit_gen_hb%ija_aliasK)
        if (allocated(excit_gen_hb%ija_weights_tot)) deallocate(excit_gen_hb%ija_weights_tot)
        if (allocated(excit_gen_hb%ijab_weights)) deallocate(excit_gen_hb%ijab_weights)
        if (allocated(excit_gen_hb%ijab_aliasU)) deallocate(excit_gen_hb%ijab_aliasU)
        if (allocated(excit_gen_hb%ijab_aliasK)) deallocate(excit_gen_hb%ijab_aliasK)
        if (allocated(excit_gen_hb%ijab_weights_tot)) deallocate(excit_gen_hb%ijab_weights_tot)
        if (allocated(excit_gen_hb%ia_weights)) deallocate(excit_gen_hb%ia_weights)

    end subroutine dealloc_excit_gen_heat_bath_t

end module excit_gens
