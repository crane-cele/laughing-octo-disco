module restart_hdf5
    ! Restart functionality based on the HDF5 library.  Note: this is only
    ! for QMC (ie FCIQMC, DMQMC or CCMC) calculations).
! [review] -  AJWT: We should consider future usage at this point before the format is entrenched!
! [reply] - JSS:
    ! Due to the use of HDF5, the format is pretty flexible (i.e. we can easily add or
    ! remove data items, though changing the data structure of the existing output is more
    ! problematic from a backward-compatibility viewpoint.

    ! We save things we absolutely need to restart the calculation, some useful
    ! metadata (to make it possible to figure out where the restart file came
    ! from) and some small data items to make life easier and avoid recomputing
    ! them.

    ! WARNING: We use some of the Fortran 2003 interfaces so HDF5 must be
    ! compiled with them enabled (i.e. --enable-fortran --enable-fortran2003 in
    ! the configure line).

    ! See HDF5 documentation and tutorials (http://www.hdfgroup.org/HDF5/ and
    ! http://www.hdfgroup.org/HDF5/Tutor/).
    ! It's a bit hard to get going (not all examples are correct/helpful/self-explanatory!)
    ! but fortunately we restrict ourselves to just a simple usage and there is not enough
    ! space to regurgitate/add thorough explanation to the full HDF5 documentation.

    ! The HDF5 structure we use is:
! [review] -  AJWT: Does order matter?
! [reply] - JSS:
    ! (Note: order does not matter as HDF5 requires explicitly statement of the group and
    ! dataspace names for each read and write operation.)
! [review] -  AJWT: How do we keep this specification consistent with what is actually done?
! [reply] - JSS: I don't think we can ensure this.  It's like any commenting---the
! [reply] - JSS: programmers must update the comments along with code.  A social rather
! [reply] - JSS: than technical issue.

    ! /                                # ROOT/
    !
    !  metadata/
    !           restart version        # Version of restart module used to produce the restart file.
! [review] -  AJWT: Probably best to say 'not currently used on read-in'
! [reply] - JSS done.
    !           hande version          # git sha1 hash.  For info only (not currently used on read-in).
    !           date                   # For info only (not currently used on read-in).
    !           uuid                   # UUID of calculation.  For info only (not currently used on read-in).
    !           calc_type              # Calculation type (as given by a parameter in calc).
    !           nprocs                 # Number of processors used in calculation.
    !           i0_length              # Number of bits in an i0 integer.
    !
    !  qmc/
    !      psips/
    !            determinants          # List of occupied determinant bit strings.
    !            populations           # population(s) on each determinant
    !            data                  # data associated with each determinant
    !            total population      # total population for each particle type.
    !      state/
    !            shift                 # shift (energy offset/population control)
    !            ncycles               # number of Monte Carlo cycles performed
    !      reference/
    !                reference determinant # reference determinant
    !                reference population  # population on reference
    !                Hilbert space reference determinant # reference determinant
    !                                  # defining Hilbert space (see comments in
    !                                  # fciqmc_data for details).
    !
    !  rng/                            # Not used yet.

    ! where XXX/ indicates a group called XXX, YYY indicates a dataset called
    ! YYY and a nested structure indicates group membership and # is used to
    ! denote a comment.

    ! NOTE: We strive to maintain backwards compatibility.  Reading in HDF5
    ! files should always test that a data item exists before reading it; if it
    ! doesn't then handle the situation gracefully (e.g. by falling back to
    ! default values).

    use hdf5, only: hid_t
    implicit none

    private
    public :: dump_restart_hdf5, read_restart_hdf5, restart_info_global

    type restart_info_t
! [review] -  AJWT: The comments in parse_input are not helpful in this regard!  More please.
! [reply] - JSS:
        ! If write_id is negative, then it was set by the user in the input file.  Set
        ! Y=-ID-1 to undo the transformation in parse_input, where Y is in the restart
        ! filename below.  If non-negative, generate Y such that the restart filename is unique.
        integer :: write_id ! ID number to write to.
        ! As for write_id but if positive find the highest possible value of Y  out of the
        ! existing restart files (assuming they have sequential values of Y).
        integer :: read_id  ! ID number to write to.
        ! Number of QMC iterations between writing out a restart file.
        integer :: write_restart_freq
        ! Stem to use for creating restart filenames (of the format restart_stem.Y.pX,
        ! where X is the processor rank and Y is a common positive integer related to
        ! write_id/read_id.
        character(8), private :: restart_stem = 'HANDE.RS'
    end type restart_info_t

    ! Global restart info store until we have a calc type which is passed
    ! around...
    type(restart_info_t) :: restart_info_global = restart_info_t(0,0,huge(0))

    ! Version id of the restart file *produced*.  Please increment if you add
    ! anything to dump_restart_hdf5!
! [review] -  AJWT: Although the git history will protect the meaning of the version number, is it advisable to document this elsewhere too?
! [review] -  AJWT: I presume we will deal with conflicts in this organically
! [reply] - JSS:
    ! Note that the restart version is not currently used anywhere but might be helpful
    ! when writing post-processing utilities which act upon restart files.
    integer, parameter :: restart_version = 1

    ! Group names...
    character(*), parameter :: gmetadata = 'metadata',  &
                               gqmc = 'qmc',            &
                               gpsips = 'psips',        &
                               gstate = 'state',        &
                               gref = 'reference',      &
                               grng = 'rng'

    ! Dataspace names...
    character(*), parameter :: drestart = 'restart version',        &
                               dcalc = 'calc type',                 &
                               dhande = 'hande version',            &
                               ddate = 'date',                      &
                               duuid = 'uuid',                      &
                               dnprocs = 'nprocs',                  &
                               di0_length = 'i0_length',            &
                               ddets = 'determinants',              &
                               dpops = 'populations',               &
                               ddata = 'data',                      &
                               dshift = 'shift',                    &
                               dncycles = 'ncycles',                &
                               dtot_pop = 'total population',       &
                               dref = 'reference determinant',      &
                               dref_pop = 'reference population @ t-1', &
                               dhsref = 'Hilbert space reference determinant'

    ! HDF5 kinds equivalent to the kinds defined in const.  Set in init_restart_hdf5.
    type h5_kinds_t
        integer(hid_t) :: i0
        integer(hid_t) :: lint
        integer(hid_t) :: p
    end type h5_kinds_t

    contains

        subroutine init_restart_hdf5(ri, write_mode, filename, kinds)

            ! Initialise restart functionality:

            ! * print information line;
            ! * create restart filename;
            ! * create HDF5 types.

            ! NOTE: HDF5 library must be opened (h5open_f) before init_restart_hdf5 is
            ! called and not closed between calling init_restart_hdf5 and operating on
            ! the restart file to ensure the HDF5 types match those calculated here.

            ! In:
            !    ri: restart information. ri%restart_stem and ri%write_id/ri%read_id (as
            !        appropriate) are used.
            !    write_mode: true for writing out a restart file, false for reading one in.
            ! Out:
            !    filename: name of the restart file.
            !    kinds: derived type containing HDF5 types which correspond to the
            !        non-standard integer and real kinds used in HANDE.

            use hdf5, only: H5_INTEGER_KIND, H5_REAL_KIND, h5kind_to_type

            use const, only: i0, lint, p
            use parallel, only: nprocs, iproc, parent
            use utils, only: int_fmt, get_unique_filename

            type(restart_info_t), intent(in) :: ri
            logical, intent(in) :: write_mode
            character(*), intent(out) :: filename
            type(h5_kinds_t), intent(out) :: kinds

            character(10) :: proc_suf
            integer :: id, ierr

            if (write_mode) then
                id = ri%write_id
            else
                id = ri%read_id
            end if

! [review] -  AJWT: A comment as to the format of the filename would be helpful.  I'd've written one, but I couldn't immediately figure it out
! [review] -  AJWT: Having looked back I saw:   the format is restart_stem.Y.pX, where X is the processor rank and Y is a common integer given by write_id or read_id.
! [reply] - JSS: see above also.
            ! Figure out filename: restart_stem.Y.pX, where Y is related to id and X is the processor rank.
            write (proc_suf,'(".p",'//int_fmt(iproc,0)//')') iproc
            if (id < 0) then
                call get_unique_filename(trim(ri%restart_stem), trim(proc_suf), write_mode, id, filename)
            else
                call get_unique_filename(trim(ri%restart_stem), trim(proc_suf), write_mode, 0, filename)
            end if

            if (parent) then
                if (write_mode) then
                    write (6,'(1X,"#",1X,"Writing restart file to",1X,a)', advance='no') trim(filename)
                else
                    write (6,'(1X,"Reading restart file from",1X,a)', advance='no') trim(filename)
                end if
                if (nprocs > 1) then
                    write (6,'(1X, "family.")')
                else
                    write (6,'(1X, ".")')
                end if
            end if

! [review] -  AJWT: I don't immediately see what these are used for.
! [review] -  AJWT: These kinds are used in the write_* functions.
! [reply] - JSS:
            ! Convert our non-standard kinds to something HDF5 understands.
            kinds%i0 = h5kind_to_type(i0, H5_INTEGER_KIND)
            kinds%p = h5kind_to_type(p, H5_REAL_KIND)
            kinds%lint = h5kind_to_type(lint, H5_INTEGER_KIND)

        end subroutine init_restart_hdf5

        subroutine dump_restart_hdf5(ri, ncycles, total_population)

            ! Write out a restart file.

            ! In:
            !    ri: restart information.  ri%restart_stem and ri%write_id are used.
            !    ncycles: number of Monte Carlo cycles performed.
            !    total_population: the total population of each particle type.

            use hdf5
            use const
            use, intrinsic :: iso_c_binding
            use report, only: VCS_VERSION, GLOBAL_UUID
            use parallel, only: nprocs, iproc, parent
            use utils, only: get_unique_filename, int_fmt

            use fciqmc_data, only: walker_dets, walker_population, walker_data, &
                                   shift, f0, hs_f0, tot_walkers,               &
                                   D0_population_cycle
            use calc, only: calc_type

            type(restart_info_t), intent(in) :: ri
            integer, intent(in) :: ncycles
            integer(lint), intent(in) :: total_population(:)
! [review] -  AJWT: This 255 character limit seems a trifle out-dated!
! [reply] - JSS: out-dated but rather convenient.  The user should not be able to change the filename stem (as it's marked private),
! [reply] - JSS: and so it leaves plenty of room for the processor rank and file id.
            character(255) :: restart_file

            ! HDF5 kinds
            type(h5_kinds_t) :: kinds
            ! HDF5 handles
            integer(hid_t) :: file_id, group_id, subgroup_id

! [review] -  AJWT: By now I'm getting the sinking feeling from the variable list that this procedure is quite monolithic!
! [reply] - JSS: not really but comments added for important variables.
            integer :: date_time(8)
            character(19) :: date_str
            integer :: ierr
            type(c_ptr) :: ptr
            ! Shape of data (sub-)array to be written out.
            integer(HSIZE_T) :: dshape2(2)
            ! Temporary variables so for copying data to which we can also call c_ptr on.
            ! This allows us to use the same array functions for writing out (the small
            ! amount of) scalar data we have to write out.
            integer(lint), allocatable, target :: tmp_pop(:)
            real(p), target :: tmp(1)

! [review] -  AJWT: Might ri be an input parameter whose value defaults to restart_info_global?
! [reply] - JSS: done.

            ! Initialise HDF5 and open file.
            call h5open_f(ierr)
            call init_restart_hdf5(ri, .true., restart_file, kinds)
! [review] -  AJWT: But the get_unique_filename above ensures this doesn't happen?
! [reply] - JSS:
            ! NOTE: if file exists (ie user requested we re-use an existing file), then it is overwritten.
            call h5fcreate_f(restart_file, H5F_ACC_TRUNC_F, file_id, ierr)

! [review] -  AJWT: This is getting a bit cryptic (but ok if you bear with it)
! [reply] - JSS: added links to HDF5 documentation at top of restart file.  Not sure what
! [reply] - JSS: else can be done without direct brain transfer or one going through the
! [reply] - JSS: HDF tutorial.
            ! --- metadata group ---
            call h5gcreate_f(file_id, gmetadata, group_id, ierr)
            call h5gopen_f(file_id, gmetadata, group_id, ierr)

                call write_string(group_id, dhande, VCS_VERSION)

! [review] -  AJWT: This doesn't appear to agree with the comments at the top
! [reply] - JSS: fixed.
                call write_string(group_id, duuid, GLOBAL_UUID)

                call date_and_time(values=date_time)
! [review] -  AJWT: What does this actually look like?
! [reply] - JSS:
                ! Print out current time and date as HH:MM:SS DD/MM/YYYY.
                write (date_str,'(2(i0.2,":"),i0.2,1X,2(i0.2,"/"),i4)') date_time(5:7), date_time(3:1:-1)
                call write_string(group_id, ddate, date_str)

                call write_integer(group_id, dnprocs, nprocs)

                call write_integer(group_id, di0_length, i0_length)

                call write_integer(group_id, drestart, restart_version)

                call write_integer(group_id, dcalc, calc_type)

            call h5gclose_f(group_id, ierr)

            ! --- qmc group ---
            call h5gcreate_f(file_id, gqmc, group_id, ierr)
            call h5gopen_f(file_id, gqmc, group_id, ierr)

                ! --- qmc/psips group ---
                call h5gcreate_f(group_id, gpsips, subgroup_id, ierr)
                call h5gopen_f(group_id, gpsips, subgroup_id, ierr)

                ! Don't write out the entire array for storing particles but
                ! rather only the slots in use...
                dshape2(1) = size(walker_dets, dim=1, kind=HSIZE_T)
                dshape2(2) = tot_walkers
                ptr = c_loc(walker_dets)
                call write_ptr(subgroup_id, ddets, kinds%i0, size(shape(walker_dets)), dshape2, ptr)

                dshape2(1) = size(walker_population, dim=1, kind=HSIZE_T)
                ptr = c_loc(walker_population)
                call write_ptr(subgroup_id, dpops, H5T_NATIVE_INTEGER, size(shape(walker_population)), dshape2, ptr)

                dshape2(1) = size(walker_data, dim=1, kind=HSIZE_T)
                ptr = c_loc(walker_data)
                call write_ptr(subgroup_id, ddata, kinds%p, size(shape(walker_data)), dshape2, ptr)

                ! Can't use c_loc on a assumed shape array.  It's small, so just
                ! copy it.
                allocate(tmp_pop(size(total_population)))
                tmp_pop = total_population
                ptr = c_loc(tmp_pop)
                call write_ptr(subgroup_id, dtot_pop, kinds%lint, size(shape(tmp_pop)), shape(tmp_pop, HSIZE_T), ptr)

                call h5gclose_f(subgroup_id, ierr)

                ! --- qmc/state group ---
                call h5gcreate_f(group_id, gstate, subgroup_id, ierr)
                call h5gopen_f(group_id, gstate, subgroup_id, ierr)

                    call write_integer(subgroup_id, dncycles, ncycles)

                    ptr = c_loc(shift)
                    call write_ptr(subgroup_id, dshift, kinds%p, size(shape(shift)), shape(shift,HSIZE_T), ptr)

                call h5gclose_f(subgroup_id, ierr)

                ! --- qmc/reference group ---
                call h5gcreate_f(group_id, gref, subgroup_id, ierr)
                call h5gopen_f(group_id, gref, subgroup_id, ierr)

                    ptr = c_loc(f0)
                    call write_ptr(subgroup_id, dref, kinds%i0, size(shape(f0)), shape(f0,HSIZE_T), ptr)

                    ptr = c_loc(hs_f0)
                    call write_ptr(subgroup_id, dhsref, kinds%i0, size(shape(hs_f0)), shape(hs_f0,HSIZE_T), ptr)
                    tmp = D0_population_cycle
                    ptr = c_loc(tmp)
                    call write_ptr(subgroup_id, dref_pop, kinds%p, 1, [1_HSIZE_T], ptr)

                call h5gclose_f(subgroup_id, ierr)

            call h5gclose_f(group_id, ierr)

            ! --- rng group ---
            call h5gcreate_f(file_id, grng, group_id, ierr)
            call h5gopen_f(file_id, grng, group_id, ierr)
            call h5gclose_f(group_id, ierr)

            ! And terminate HDF5.
            call h5fclose_f(file_id, ierr)
            call h5close_f(ierr)

        end subroutine dump_restart_hdf5

        subroutine read_restart_hdf5(ri)

            ! Read QMC data from restart file.

            ! In:
            !    ri: restart information.  ri%restart_stem and ri%read_id are used.

            use hdf5
            use errors, only: stop_all
            use const

            use fciqmc_data, only: walker_dets, walker_population, walker_data,  &
                                   shift, tot_nparticles, f0, hs_f0,             &
                                   D0_population, mc_cycles_done, tot_walkers
            use calc, only: calc_type, exact_diag, lanczos_diag, mc_hilbert_space
            use parallel, only: nprocs

            type(restart_info_t), intent(in) :: ri

            ! HDF5 kinds
            type(h5_kinds_t) :: kinds
            ! HDF5 handles
            integer(hid_t) :: file_id, group_id, subgroup_id, dset_id, dspace_id

            character(255) :: restart_file
            integer :: restart_version_restart, calc_type_restart, nprocs_restart
            integer :: i0_length_restart
            type(c_ptr) :: ptr
            integer :: ierr
            real(p), target :: tmp(1)

            integer(HSIZE_T) :: dims(size(shape(walker_dets))), maxdims(size(shape(walker_dets)))

! [review] -  AJWT: This seems like needless duplication of what happens in dump_restart_hdf5 which could be put in a procedure
! [reply] - JSS: abstracted into a common init procedure.

            ! Initialise HDF5 and open file.
            call h5open_f(ierr)
            call init_restart_hdf5(ri, .false., restart_file, kinds)
            call h5fopen_f(restart_file, H5F_ACC_RDONLY_F, file_id, ierr)

! [review] -  AJWT: Here endeth the duplication
            ! --- metadata group ---
            call h5gopen_f(file_id, gmetadata, group_id, ierr)

                call read_integer(group_id, dnprocs, nprocs_restart)

                call read_integer(group_id, drestart, restart_version_restart)

                call read_integer(group_id, di0_length, i0_length_restart)

                call read_integer(group_id, dcalc, calc_type_restart)


! [review] -  AJWT: While bit strings are nice, I think the code below lacks modularity.
!              I foresee a time when the calc_type format will change, and the code
!              below will be a pain.  Perhaps some sort of interface for this.
!             In particular, I don't think the restart_read should be dealing with this sort of thing.
! [reply] - JSS: leave as todo for now.
                ! [todo] - Allow restart files for one calculation types to be used to
                ! [todo] - restart a (suitably compatible) different calculation.
                ! Different calc types are either not compatible or require
                ! hyperslabs (fewer particle types) or require copying (more
                ! particle types).
                ! Clear the flags for non-QMC calculations (which aren't
                ! restarted anyway and don't affect the QMC calculation).
                calc_type_restart = ieor(calc_type, calc_type_restart)
                calc_type_restart = iand(calc_type_restart, not(exact_diag))
                calc_type_restart = iand(calc_type_restart, not(lanczos_diag))
                calc_type_restart = iand(calc_type_restart, not(mc_hilbert_space))
                if (calc_type_restart /= 0) &
                    call stop_all('read_restart_hdf5', &
                                  'Restarting with different calculation types not supported.  Please implement.')
                ! Different restart versions require graceful handling of the
                ! additions/removals.
                if (restart_version /= restart_version_restart) &
                    call stop_all('read_restart_hdf5', &
                                  'Restarting from a different restart version not supported.  Please implement.')
                ! Different processor counts requires figuring out if
                ! a determinant should be on the processor or not (and reading
                ! in chunks).
                if (nprocs /= nprocs_restart) &
                    call stop_all('read_restart_hdf5', &
                                  'Restarting on a different number of processors not supported.  Please implement.')

                if (i0_length /= i0_length_restart) &
                    call stop_all('read_restart_hdf5', &
                                  'Restarting with a different (i0) bit string length not supported.  Please implement.')
            call h5gclose_f(group_id, ierr)

            ! --- qmc group ---
            call h5gopen_f(file_id, gqmc, group_id, ierr)

                ! --- qmc/psips group ---
                call h5gopen_f(group_id, gpsips, subgroup_id, ierr)

                ! Figure out how many determinants we wrote out...
                ! walker_dets has rank 2, so need not look that up!
                call h5dopen_f(subgroup_id, ddets, dset_id, ierr)
                call h5dget_space_f(dset_id, dspace_id, ierr)
                call h5sget_simple_extent_dims_f(dspace_id, dims, maxdims, ierr)
                call h5dclose_f(dset_id, ierr)
                ! Number of determinants is the last index...
                tot_walkers = dims(size(dims))

                ptr = c_loc(walker_dets)
                call read_ptr(subgroup_id, ddets, kinds%i0, ptr)

                ptr = c_loc(walker_population)
                call read_ptr(subgroup_id, dpops, H5T_NATIVE_INTEGER, ptr)

                ptr = c_loc(walker_data)
                call read_ptr(subgroup_id, ddata, kinds%p, ptr)

                ptr = c_loc(tot_nparticles)
                call read_ptr(subgroup_id, dtot_pop, kinds%lint, ptr)

                call h5gclose_f(subgroup_id, ierr)

                ! --- qmc/state group ---
                call h5gopen_f(group_id, gstate, subgroup_id, ierr)

                    call read_integer(subgroup_id, dncycles, mc_cycles_done)

                    ptr = c_loc(shift)
                    call read_ptr(subgroup_id, dshift, kinds%p, ptr)

                call h5gclose_f(subgroup_id, ierr)

                ! --- qmc/reference group ---
                call h5gopen_f(group_id, gref, subgroup_id, ierr)

                    ptr = c_loc(f0)
                    call read_ptr(subgroup_id, dref, kinds%i0, ptr)

                    ptr = c_loc(hs_f0)
                    call read_ptr(subgroup_id, dhsref, kinds%i0, ptr)

                    ptr = c_loc(tmp)
                    call read_ptr(subgroup_id, dref_pop, kinds%p, ptr)
                    D0_population = tmp(1)

                call h5gclose_f(subgroup_id, ierr)

            call h5gclose_f(group_id, ierr)

            ! --- rng group ---
            call h5gopen_f(file_id, grng, group_id, ierr)
            call h5gclose_f(group_id, ierr)

            ! And terminate HDF5.
            call h5fclose_f(file_id, ierr)
            call h5close_f(ierr)

        end subroutine read_restart_hdf5

        ! === Helper procedures: writing ===

! [review] -  AJWT: The write_* lends it self to being overloaded to a single function write_hdf5.  Similarly read_*
        subroutine write_string(id, dset, string)

            ! Write a string to an open HDF5 file/group.

            ! In:
            !    id: file or group HD5 identifier.
            !    dset: dataset name.
            !    string: string to write out.

            use hdf5

            integer(hid_t), intent(in) :: id
            character(*), intent(in) :: dset, string

            integer(hid_t) :: type_id, dspace_id, dset_id
            integer :: ierr

! [review] -  AJWT: This indicates perhaps a misunderstanding of the format which might not be good news
! [review] -  AJWT:  for compatability.  Any chance this can be looked at again?
! [reply] - JSS: Misled by documentation and examples indicating h5dwrite_vl_f was the way to write out a string.  Despite the
! [reply] - JSS: documentation for h5dwrite_vl_f claiming otherwise, an inspection of the HDF5 source reveals that h5dwrite_vl_f
! [reply] - JSS: is only declared for arrays.  However, a careful look at the documentation reveals strings can be written out as
! [reply] - JSS: scalars, if one declares their length using h5tset_size_f.  The term 'variable length' is hence a red herring, as
! [reply] - JSS: one can write strings out which have lengths not known at compile-time using the standard scalar approach...

            ! Set up fortran string type of *this* length...
            call h5tcopy_f(H5T_FORTRAN_S1, type_id, ierr)
            call h5tset_size_f(type_id, len(string, HSIZE_T), ierr)

            ! Create space and write string.
            call h5screate_f(H5S_SCALAR_F, dspace_id, ierr)
            call h5dcreate_f(id, dset, type_id, dspace_id, dset_id, ierr)
            call h5dwrite_f(dset_id, type_id, string, [0_HSIZE_T], ierr)
            call h5sclose_f(dspace_id, ierr)
            call h5dclose_f(dset_id, ierr)

            ! Release fortran string type.
            call h5tclose_f(type_id, ierr)

        end subroutine write_string

        subroutine write_integer(id, dset, val)

            ! Write an integer to an open HDF5 file/group.

            ! In:
            !    id: file or group HD5 identifier.
            !    dset: dataset name.
            !    val: integer to write out.

            use hdf5

            integer(hid_t), intent(in) :: id
            character(*), intent(in) :: dset
            integer, intent(in) :: val

            integer(hid_t) :: dspace_id, dset_id
            integer :: ierr

            call h5screate_f(H5S_SCALAR_F, dspace_id, ierr)
            call h5dcreate_f(id, dset, H5T_NATIVE_INTEGER, dspace_id, dset_id, ierr)

            call h5dwrite_f(dset_id, H5T_NATIVE_INTEGER, val, [0_HSIZE_T,0_HSIZE_T], ierr)

            call h5dclose_f(dset_id, ierr)
            call h5sclose_f(dspace_id, ierr)

        end subroutine write_integer

! [review] -  AJWT: This looks potentially dangerous - if dtype differs from the actual type of arr_ptr
!              Might an overloaded interface not be better?
        subroutine write_ptr(id, dset, dtype, arr_rank, arr_dim, arr_ptr)

            ! Write an array to an open HDF5 file/group.

            ! In:
            !    id: file or group HD5 identifier.
            !    dset: dataset name.
            !    dtype: HDF5 data type of array.
            !    arr_rank: rank of array.
            !    arr_dim: size of array along each dimension.
            !    arr_ptr: C pointer to first element in array to be written out.

            ! NOTE: get dtype from h5kind_to_type if not using a native HDF5
            ! Fortran type.

            use hdf5
            use, intrinsic :: iso_c_binding

            integer(hid_t), intent(in) :: id
            character(*), intent(in) :: dset
            integer(hid_t), intent(in) :: dtype
            integer, intent(in) :: arr_rank
            integer(hsize_t), intent(in) :: arr_dim(:)
            type(c_ptr), intent(in) :: arr_ptr

            integer :: ierr
            integer(hid_t) :: dspace_id, dset_id

            call h5screate_simple_f(arr_rank, arr_dim, dspace_id, ierr)
            call h5dcreate_f(id, dset, dtype, dspace_id, dset_id, ierr)

            call h5dwrite_f(dset_id, dtype, arr_ptr, ierr)

            call h5dclose_f(dset_id, ierr)
            call h5sclose_f(dspace_id, ierr)

        end subroutine write_ptr

        ! === Helper procedures: reading ===

        subroutine read_integer(id, dset, val)

            ! Read an integer from an open HDF5 file/group.

            ! In:
            !    id: file or group HD5 identifier.
            !    dset: dataset name.
            ! Out:
            !    val: integer read from HDF5 file.

            use hdf5

            integer(hid_t), intent(in) :: id
            character(*), intent(in) :: dset
            integer, intent(out) :: val

            integer(hid_t) :: dset_id
            integer :: ierr

            call h5dopen_f(id, dset, dset_id, ierr)
            call h5dread_f(dset_id, H5T_NATIVE_INTEGER, val, [0_HSIZE_T,0_HSIZE_T], ierr)
            call h5dclose_f(dset_id, ierr)

        end subroutine read_integer

! [review] -  AJWT: I feel the frisson of data overflow and horrible bugs for the future in this code.
!               Perhaps at least a length check?
        subroutine read_ptr(id, dset, dtype, arr_ptr)

            ! Read an array from an open HDF5 file/group.

            ! In:
            !    id: file or group HD5 identifier.
            !    dset: dataset name.
            !    dtype: HDF5 data type of array.
            ! In/Out:
            !    arr_ptr: C pointer to first element in array to read.  On
            !        output, the dataset is store in the array pointed to by
            !        arr_ptr.

            ! NOTE: get dtype from h5kind_to_type if not using a native HDF5
            ! Fortran type.

            use hdf5
            use, intrinsic :: iso_c_binding

            integer(hid_t), intent(in) :: id
            character(*), intent(in) :: dset
            integer(hid_t), intent(in) :: dtype
            type(c_ptr), intent(inout) :: arr_ptr

            integer :: ierr
            integer(hid_t) :: dset_id

            call h5dopen_f(id, dset, dset_id, ierr)
            call h5dread_f(dset_id, dtype, arr_ptr, ierr)
            call h5dclose_f(dset_id, ierr)

        end subroutine read_ptr

end module restart_hdf5
