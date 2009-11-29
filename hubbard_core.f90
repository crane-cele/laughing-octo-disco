program hubbard_fciqmc

use report, only: environment_report
use parse_input, only: read_input
use hubbard, only: init_basis_fns

call init_calc()

contains

    subroutine init_calc()

        ! Initialise the calculation.
        ! Print out information about the compiled executable, 
        ! read input options and initialse the system and basis functions
        ! to be used.

        write (6,'(/,a8,/)') 'Hubbard'

        call environment_report()

        call read_input()

        call init_basis_fns()

    end subroutine init_calc

end program hubbard_fciqmc
