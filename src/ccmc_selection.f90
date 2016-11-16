module ccmc_selection

! Module containing all ccmc selection subroutines.
! For full explanation see top of ccmc.F90.

use const, only: i0, int_p, int_64, p, dp, debug, depsilon

implicit none

contains

    subroutine select_cluster(rng, sys, psip_list, f0, ex_level, linked_ccmc, nattempts, normalisation, &
                              initiator_pop, D0_pos, cumulative_excip_pop, tot_excip_pop, min_size, max_size, &
                              logging_info, cdet, cluster)

        ! Select a random cluster of excitors from the excitors on the
        ! processor.  A cluster of excitors is itself an excitor.  For clarity
        ! (if not technical accuracy) in comments we shall distinguish between
        ! the cluster of excitors and a single excitor, from a set of which the
        ! cluster is formed.

        ! In:
        !    sys: system being studied
        !    psip_list: particle_t object containing current excip distribution on
        !       this processor.
        !    f0: bit string of the reference.
        !    ex_level: max number of excitations from the reference to include in
        !        the Hilbert space.
        !    nattempts: the number of times (on this processor) a random cluster
        !        of excitors is generated in the current timestep.
        !    linked_ccmc: if true then only sample linked clusters.
        !    normalisation: intermediate normalisation factor, N_0, where we use the
        !       wavefunction ansatz |\Psi_{CC}> = N_0 e^{T/N_0} | D_0 >.
        !    initiator_pop: the population above which a determinant is an initiator.
        !    D0_pos: position in the excip list of the reference.  Must be negative
        !       if the reference is not on the processor.
        !    cumulative_excip_population: running cumulative excip population on
        !        all excitors; i.e. cumulative_excip_population(i) = sum(particle_t%pops(1:i)).
        !    tot_excip_pop: total excip population.
        !    min_size: the minimum size cluster to allow.
        !    max_size: the maximum size cluster to allow.
        !    logging_info: derived type containing information on currently logging status

        ! NOTE: cumulative_excip_pop and tot_excip_pop ignore the population on the
        ! reference as excips on the reference cannot form a cluster and the rounds the
        ! population on all other excitors to the nearest integer (for convenience--see
        ! comments in do_ccmc).  Both these quantities should be generated by
        ! cumulative_population (or be in the same format).

        ! In/Out:
        !    rng: random number generator.
        !    cdet: information about the cluster of excitors applied to the
        !        reference determinant.  This is a bare det_info_t variable on input
        !        with only the relevant fields allocated.  On output the
        !        appropriate (system-specific) fields have been filled by
        !        decoding the bit string of the determinant formed from applying
        !        the cluster to the reference determinant.
        !    cluster:
        !        Additional information about the cluster of excitors.  On
        !        input this is a bare cluster_t variable with the excitors array
        !        allocated to the maximum number of excitors in a cluster.  On
        !        output all fields in cluster have been set.

        use determinants, only: det_info_t
        use ccmc_data, only: cluster_t
        use ccmc_utils, only: convert_excitor_to_determinant, collapse_cluster
        use excitations, only: get_excitation_level
        use dSFMT_interface, only: dSFMT_t, get_rand_close_open
        use qmc_data, only: particle_t
        use proc_pointers, only: decoder_ptr
        use utils, only: factorial
        use search, only: binary_search
        use sort, only: insert_sort
        use parallel, only: nprocs
        use system, only: sys_t
        use logging, only: write_logging_stoch_selection, logging_t

        type(sys_t), intent(in) :: sys
        type(particle_t), intent(in), target :: psip_list
        integer(i0), intent(in) :: f0(sys%basis%string_len)
        integer, intent(in) :: ex_level
        integer(int_64), intent(in) :: nattempts
        logical, intent(in) :: linked_ccmc
        integer, intent(in) :: D0_pos
        complex(p), intent(in) :: normalisation
        real(p), intent(in) :: initiator_pop
        real(p), intent(in) :: cumulative_excip_pop(:), tot_excip_pop
        integer :: min_size, max_size
        type(dSFMT_t), intent(inout) :: rng
        type(det_info_t), intent(inout) :: cdet
        type(cluster_t), intent(inout) :: cluster
        type(logging_t), intent(in) :: logging_info

        real(dp) :: rand
        real(p) :: psize
        complex(p) :: cluster_population, excitor_pop
        integer :: i, pos, prev_pos
        real(p) :: pop(max_size)
        logical :: hit, allowed, all_allowed

        ! We shall accumulate the factors which comprise cluster%pselect as we go.
        !   cluster%pselect = n_sel p_size p_clust
        ! where
        !   n_sel   is the number of cluster selections made;
        !   p_size  is the probability of choosing a cluster of that size;
        !   p_clust is the probability of choosing a specific cluster given
        !           the choice of size.

        ! Each processor does nattempts.
        ! However:
        ! * if min_size=0, then each processor is allowed to select the reference (on
        !   average) nattempts/2 times.  Hence in order to have selection probabilities
        !   consistent and independent of the number of processors being used (which
        !   amounts to a processor-dependent timestep scaling), we need to multiply the
        !   probability the reference is selected by nprocs.
        ! * assuming each excitor spends (on average) the same amount of time on each
        !   processor, the probability that X different excitors are on the same processor
        !   at a given timestep is 1/nprocs^{X-1).
        ! The easiest way to handle both of these is to multiply the number of attempts by
        ! the number of processors here and then deal with additional factors of 1/nprocs
        ! when creating composite clusters.
        ! NB within a processor those nattempts can be split amongst OpenMP
        ! threads though that doesn't affect this probability.
        cluster%pselect = real(nattempts*nprocs, p)

        ! Select the cluster size, i.e. the number of excitors in a cluster.
        ! For a given truncation level, only clusters containing at most
        ! ex_level+2 excitors.
        ! Following the process described by Thom in 'Initiator Stochastic
        ! Coupled Cluster Theory' (unpublished), each size, n_s, has probability
        ! p(n_s) = 1/2^(n_s+1), n_s=0,ex_level and p(ex_level+2)
        ! is such that \sum_{n_s=0}^{ex_level+2} p(n_s) = 1.

        ! This procedure is modified so that clusters of size min_size+n_s
        ! has probability 1/2^(n_s+1), and the max_size picks up the remaining
        ! probability from the series.
        rand = get_rand_close_open(rng)
        psize = 0.0_p
        cluster%nexcitors = -1
        do i = 0, max_size-min_size-1
            psize = psize + 1.0_p/2**(i+1)
            if (rand < psize) then
                ! Found size!
                cluster%nexcitors = i+min_size
                cluster%pselect = cluster%pselect/2**(i+1)
                exit
            end if
        end do
        ! If not set, then must be the largest possible cluster
        if (cluster%nexcitors == -1) then
            cluster%nexcitors = max_size
            cluster%pselect = cluster%pselect*(1.0_p - psize)
        end if

        ! If could be using logging set to easily identifiable nonsense value.
        if (debug) pop = -1_int_p

        ! Initiator approximation.
        ! This is sufficiently quick that we'll just do it in all cases, even
        ! when not using the initiator approximation.  This matches the approach
        ! used by Alex Thom in 'Initiator Stochastic Coupled Cluster Theory'
        ! (unpublished).
        ! Assume all excitors in the cluster are initiators (initiator_flag=0)
        ! until proven otherwise (initiator_flag=1).
        cdet%initiator_flag = 0

        ! Assume cluster is allowed unless collapse_cluster finds out otherwise
        ! when collapsing/combining excitors or if it could never have been
        ! valid
        allowed = min_size <= max_size
        ! For linked coupled cluster we keep building the cluster after a
        ! disallowed excitation so need to know if there has been a disallowed
        ! excitation at all
        all_allowed = allowed

        select case(cluster%nexcitors)
        case(0)
            call create_null_cluster(sys, f0, cluster%pselect, normalisation, initiator_pop, &
                                    cdet, cluster)
        case default
            ! Select cluster from the excitors on the current processor with
            ! probability for choosing an excitor proportional to the excip
            ! population on that excitor.  (For convenience, we use a probability
            ! proportional to the ceiling(pop), as it makes finding the right excitor
            ! much easier, especially for the non-composite algorithm, as well as
            ! selecting excitors with the correct (relative) probability.  The
            ! additional fractional weight is taken into account in the amplitude.)
            !
            ! Rather than selecting one excitor at a time and adding it to the
            ! cluster, select all excitors and then find their locations and
            ! apply them.  This allows us to sort by population first (as the
            ! number of excitors is small) and hence allows for a more efficient
            ! searching of the cumulative population list.

            do i = 1, cluster%nexcitors
                ! Select a position in the excitors list.
                pop(i) = get_rand_close_open(rng)*tot_excip_pop
            end do
            call insert_sort(pop(:cluster%nexcitors))
            prev_pos = 1
            do i = 1, cluster%nexcitors
                call binary_search(cumulative_excip_pop, pop(i), prev_pos, psip_list%nstates, hit, pos)
                ! Not allowed to select the reference as it is not an excitor.
                ! Because we treat (for the purposes of the cumulative
                ! population) the reference to have 0 excips, then
                ! cumulative_excip_pop(D0_pos) = cumulative_excip_pop(D0_pos-1).
                ! The binary search algorithm assumes each value in the array
                ! being searched is unique, which is not true, so we can
                ! accidentally find D0_pos.  As we want to find pos such that
                ! cumulative_excip_pop(pos-1) < pop <= cumulative_excip_pop(pos),
                ! then this means we actually need the slot before D0_pos.
                ! Correcting for this accident is much easier than producing an
                ! array explicitly without D0...
                ! If contain multiple spaces we can have this in a more general
                ! case, where an excitor has population in another space but not
                ! that which we're currently concerned with. More general test
                ! should account for this.
                do
                    if (pos == 1) exit
                    if (abs(cumulative_excip_pop(pos) - cumulative_excip_pop(pos-1)) > depsilon) exit
                    pos = pos - 1
                end do
                if (sys%read_in%comp) then
                    excitor_pop = cmplx(psip_list%pops(1,pos), psip_list%pops(2,pos),p)/psip_list%pop_real_factor
                else
                    excitor_pop = real(psip_list%pops(1,pos),p)/psip_list%pop_real_factor
                end if
                if (i == 1) then
                    ! First excitor 'seeds' the cluster:
                    cdet%f = psip_list%states(:,pos)
                    cdet%data => psip_list%dat(:,pos) ! Only use if cluster is non-composite!
                    cluster_population = excitor_pop
                    ! Counter the additional *nprocs above.
                    cluster%pselect = cluster%pselect/nprocs
                else
                    call collapse_cluster(sys%basis, f0, psip_list%states(:,pos), excitor_pop, cdet%f, &
                                          cluster_population, allowed)
                    if (.not.allowed) then
                        if (.not. linked_ccmc) exit
                        all_allowed = .false.
                    end if
                    ! Each excitor spends the same amount of time on each processor on
                    ! average.  If this excitor is different from the previous excitor,
                    ! then the probability this excitor is on the same processor as the
                    ! previous excitor is 1/nprocs.  (Note choosing the same excitor
                    ! multiple times is valid in linked CC.)
                    if (pos /= prev_pos) cluster%pselect = cluster%pselect/nprocs
                end if
                ! If the excitor's population is below the initiator threshold, we remove the
                ! initiator status for the cluster
                if (abs(excitor_pop) <= initiator_pop) cdet%initiator_flag = 3
                ! Probability of choosing this excitor = pop/tot_pop.
                cluster%pselect = (cluster%pselect*abs(excitor_pop))/tot_excip_pop
                cluster%excitors(i)%f => psip_list%states(:,pos)
                prev_pos = pos
            end do

            if (allowed) then
                cluster%excitation_level = get_excitation_level(f0, cdet%f)
                ! To contribute the cluster must be within a double excitation of
                ! the maximum excitation included in the CC wavefunction.
                allowed = cluster%excitation_level <= ex_level+2
            end if

            if (allowed.or.linked_ccmc) then
                ! We chose excitors with a probability proportional to their
                ! occupation.  However, because (for example) the cluster t_X t_Y
                ! and t_Y t_X collapse onto the same excitor (where X and Y each
                ! label an excitor), the probability of selecting a given cluster is
                ! proportional to the number of ways the cluster could have been
                ! formed.  (One can view this factorial contribution as the
                ! factorial prefactors in the series expansion of e^T---see Eq (8)
                ! in the module-level comments.)
                ! If two excitors in the cluster are the same, the factorial
                ! overcounts the number of ways the cluster could have been formed
                ! but the extra factor(s) of 2 are cancelled by a similar
                ! overcounting in the calculation of hmatel.
                cluster%pselect = cluster%pselect*factorial(cluster%nexcitors)

                ! Sign change due to difference between determinant
                ! representation and excitors and excitation level.
                call convert_excitor_to_determinant(cdet%f, cluster%excitation_level, cluster%cluster_to_det_sign, f0)
                call decoder_ptr(sys, cdet%f, cdet)

                ! Normalisation factor for cluster%amplitudes...
                cluster%amplitude = cluster_population/(normalisation**(cluster%nexcitors-1))
            else
                ! Simply set excitation level to a too high (fake) level to avoid
                ! this cluster being used.
                cluster%excitation_level = huge(0)
            end if

            if (.not.all_allowed) cluster%excitation_level = huge(0)

        end select

        if (debug) call write_logging_stoch_selection(logging_info, cluster%nexcitors, cluster%excitation_level, pop, &
                min(sys%nel, ex_level+2), cluster%pselect, cluster%amplitude, allowed)

    end subroutine select_cluster

    subroutine create_null_cluster(sys, f0, prob, D0_normalisation, initiator_pop, cdet, cluster)

        ! Create a cluster with no excitors in it, and set it to have
        ! probability of generation prob.

        ! In:
        !    sys: system being studied
        !    f0: bit string of the reference
        !    prob: The probability we set in it of having been generated
        !    D0_normalisation:  The number of excips at the reference (which
        !        will become the amplitude of this cluster)
        !    initiator_pop: the population above which a determinant is an initiator.

        ! In/Out:
        !    cdet: information about the cluster of excitors applied to the
        !        reference determinant.  This is a bare det_info variable on input
        !        with only the relevant fields allocated.  On output the
        !        appropriate (system-specific) fields have been filled by
        !        decoding the bit string of the determinant formed from applying
        !        the cluster to the reference determinant.
        !    cluster:
        !        Additional information about the cluster of excitors.  On
        !        input this is a bare cluster_t variable with the excitors array
        !        allocated to the maximum number of excitors in a cluster.  On
        !        output all fields in cluster have been set.

        use system, only: sys_t
        use determinants, only: det_info_t
        use ccmc_data, only: cluster_t
        use proc_pointers, only: decoder_ptr

        type(sys_t), intent(in) :: sys
        integer(i0), intent(in) :: f0(sys%basis%string_len)
        real(p), intent(in) :: prob, initiator_pop
        complex(p), intent(in) :: D0_normalisation
        type(det_info_t), intent(inout) :: cdet
        type(cluster_t), intent(inout) :: cluster

        ! Note only one null cluster to choose => p_clust = 1.
        cluster%pselect = prob

        cluster%nexcitors = 0

        ! Initiator approximation.
        ! This is sufficiently quick that we'll just do it in all cases, even
        ! when not using the initiator approximation.  This matches the approach
        ! used by Alex Thom in 'Initiator Stochastic Coupled Cluster Theory'
        ! (unpublished).
        ! Surely the reference has an initiator population?
        cdet%initiator_flag = 0

        ! Must be the reference.
        cdet%f = f0
        cluster%excitation_level = 0
        cluster%amplitude = D0_normalisation
        cluster%cluster_to_det_sign = 1
        ! If not initiator something has gone seriously wrong and the CC
        ! approximation is (most likely) not suitably for this system.
        ! Let the user be an idiot if they want to be...
        if (abs(D0_normalisation) <= initiator_pop) cdet%initiator_flag = 3

        call decoder_ptr(sys, cdet%f, cdet)

    end subroutine create_null_cluster

    subroutine select_cluster_non_composite(sys, psip_list, f0, iattempt, initiator_pop, &
                                            cdet, cluster)

        ! Select (deterministically) the non-composite cluster containing only
        ! the single excitor iexcitor and set the same information as select_cluster.


        ! In:
        !    sys: system being studied
        !    psip_list: particle_t object containing current excip distribution on
        !       this processor.
        !    f0: bit string of the reference
        !    iexcitor: the index (in range [1,nstates]) of the excitor to select.
        !    initiator_pop: the population above which a determinant is an initiator.

        ! In/Out:
        !    cdet: information about the cluster of excitors applied to the
        !        reference determinant.  This is a bare det_info variable on input
        !        with only the relevant fields allocated.  On output the
        !        appropriate (system-specific) fields have been filled by
        !        decoding the bit string of the determinant formed from applying
        !        the cluster to the reference determinant.
        !    cluster:
        !        Additional information about the cluster of excitors.  On
        !        input this is a bare cluster_t variable with the excitors array
        !        allocated to the maximum number of excitors in a cluster.  On
        !        output all fields in cluster have been set.

        use system, only: sys_t
        use determinants, only: det_info_t
        use ccmc_data, only: cluster_t
        use ccmc_utils, only: convert_excitor_to_determinant, get_pop_contrib
        use excitations, only: get_excitation_level
        use qmc_data, only: particle_t
        use search, only: binary_search
        use proc_pointers, only: decoder_ptr

        type(sys_t), intent(in) :: sys
        type(particle_t), intent(in), target :: psip_list
        integer(i0), intent(in) :: f0(sys%basis%string_len)
        integer(int_64), intent(in) :: iattempt
        real(p), intent(in) :: initiator_pop
        type(det_info_t), intent(inout) :: cdet
        type(cluster_t), intent(inout) :: cluster
        complex(p) :: excitor_pop

        ! Rather than looping over individual excips we loop over different sites. This is
        ! because we want to stochastically set the number of spawning attempts such that
        ! we on average select each excitor a number of times proportional to the absolute
        ! population. As such, we can't specify the total number of selections beforehand
        ! within do_ccmc.

        ! As iterating deterministically through all noncomposite clusters, pselect = 1
        ! exactly.
        ! This excitor can only be selected on this processor and only one excitor is
        ! selected in the cluster, so unlike selecting the reference or composite
        ! clusters, there are no additional factors of nprocs or 1/nprocs to include.

        cluster%pselect = 1.0_p

        cluster%nexcitors = 1

        ! Initiator approximation.
        ! This is sufficiently quick that we'll just do it in all cases, even
        ! when not using the initiator approximation.  This matches the approach
        ! used by Alex Thom in 'Initiator Stochastic Coupled Cluster Theory'
        ! (unpublished).
        ! Assume all excitors in the cluster are initiators (initiator_flag=0)
        ! until proven otherwise (initiator_flag=1).
        cdet%initiator_flag = 0

        cdet%f = psip_list%states(:,iattempt)
        cdet%data => psip_list%dat(:,iattempt)
        cluster%excitors(1)%f => psip_list%states(:,iattempt)
        if (sys%read_in%comp) then
            excitor_pop = cmplx(psip_list%pops(1,iattempt), psip_list%pops(2,iattempt), p)/psip_list%pop_real_factor
        else
            excitor_pop = cmplx(psip_list%pops(1,iattempt), 0.0_p, p)/psip_list%pop_real_factor
        end if

        if (abs(excitor_pop) <= initiator_pop) cdet%initiator_flag = 3
        cluster%excitation_level = get_excitation_level(f0, cdet%f)
        cluster%amplitude = excitor_pop

        ! Sign change due to difference between determinant
        ! representation and excitors and excitation level.
        call convert_excitor_to_determinant(cdet%f, cluster%excitation_level, cluster%cluster_to_det_sign, f0)
        call decoder_ptr(sys, cdet%f, cdet)

    end subroutine select_cluster_non_composite

end module ccmc_selection
