#!/usr/bin/python
'''Produce a makefile for compiling the source code for a specified target/configuration.
The resultant makefile requires makedepf90 (http://personal.inet.fi/private/erikedelmann/makedepf90/)
to produce a list of dependencies.

Usage:
    ./mkconfig.py [options] configuration

where [options] are:
    -h,--help   Print this message and exit.
    -c,--config Print out the available configurations and their settings.
    -d,--debug  Turn on debug flags (and turn off all optimisations).
'''

import os,pprint,sys

class makefile_flags(dict):
    '''Initialise dictionary with all makefile variables not given set to be empty.

    Usage: makefile_flags(FC='ifort',FFLAGS='-O3') creates a dictionary of the 
    makefile flags and sets FC and FFLAGS, with all other flags existing but set to 
    be empty.'''
    def __init__(self,**kwargs):
        dict.__init__(self,FC='',
                           FFLAGS='',
                           CPPDEFS='',
                           CPPFLAGS='',
                           LD='',
                           LDFLAGS='',
                           LIBS='-ltrlan -llapack -lblas',
                           MODULE_FLAG='',) # Flag compiler uses for setting the directory 
                                            # in which to place/search for .mod files.
                                            # Must be followed by $(DEST).  This is to 
                                            # accommodate the compilers which want a space
                                            # after the flag as well as those that don't!
                                            # e.g. for g95 MODULE_FLAG='-fmod=$(DEST)' 
                                            # whilst for gfortran MODULE_FLAG='-J $(DEST)'.
        self.update(**kwargs)

#======================================================================
# Local settings.

program_name='hubbard.x'

# Directory in which compiled objects are placed.
dest='dest'

# Directory in which the compiled executable is placed.
exe='bin'

# List of directories (colon-separated) containing the source files.
vpath='src:lib'

# Space separated list of file extensions for the source files.
source_ext='.f90 .F90'

#======================================================================
# Edit this section to add new configurations.

ifort=makefile_flags(
          FC='ifort',
          FFLAGS='',
          LD='ifort',
          MODULE_FLAG='-module $(DEST)'
      )

# Use makefile_flags(**ifort) rather than just =ifort so that 
# ifort_mpi has the makefile_flags class, rather than being a normal
# dict. This enables us to search for all created configurations automatically.
# The same can be achieved using ifort_mpi=copy.copy(ifort), but I chose not to.
ifort_mpi=makefile_flags(**ifort) # Initialise with the same settings as the serial platform.
ifort_mpi.update(                 # Now change only the settings we want to...
          FC='mpif90',
          LD='mpif90',
          CPPDEFS='-D_PARALLEL',
          LIBS='-ltrlan_mpi -lscalapack -lblacsc -lblacsf77 -lblacsmpi -llapack -lblas',
      )

gfortran=makefile_flags(
          FC='gfortran',
          FFLAGS='-O3 -fbounds-check',
          LD='gfortran',
          MODULE_FLAG='-M $(DEST)',
      )

gfortran_mpi=makefile_flags(**gfortran)
gfortran_mpi.update(
          FC='mpif90',
          FFLAGS='-I /usr/local/shared/suse-10.3/x86_64/openmpi-1.2.6-gnu/lib',
          LD='mpif90',
          CPPDEFS='-D_PARALLEL',
          LIBS='-ltrlan_mpi -lscalapack -lblacsc -lblacsf77 -lblacsmpi -llapack -lblas',
      )

g95=makefile_flags(
          FC='g95',
          FFLAGS='-fbounds-check',
          LD='g95',
          MODULE_FLAG='-fmod=$(DEST)',
      )

nag=makefile_flags(
          FC='nagfor',
          CPPFLAGS='-DNAGF95',
          LD='nagfor',
          MODULE_FLAG='-mdir $(DEST)',
      )

pgf90=makefile_flags(
          FC='pgf90',
          FFLAGS='-O3',
          LD='pgf90',
          MODULE_FLAG='-module $(DEST)'
      )

pgf90_mpi=makefile_flags(**pgf90)
pgf90_mpi.update(
          FC='mpif90',
          LD='mpif90',
          CPPDEFS='-D_PARALLEL',
          LIBS='-ltrlan_mpi -lscalapack -lblacsc -lblacsf77 -lblacsmpi -llapack -lblas',
      )

pathf95=makefile_flags(
          FC='pathf95',
          FFLAGS='',
          LD='pathf95',
          MODULE_FLAG='-module $(DEST)'
      )

#======================================================================

# Get list of possible platforms.
configurations={}
for name,value in locals().items():
    if value.__class__==makefile_flags().__class__:
        configurations[name]=value

makefile_template='''# Generated by mkconfig.py.

SHELL=/bin/bash # For our sanity!

#-----
# Compiler configuration.

FC=%(FC)s
FFLAGS=-I $(DEST) %(FFLAGS)s

CPPDEFS=%(CPPDEFS)s -D_VCS_VER='$(VCS_VER)'
CPPFLAGS=%(CPPFLAGS)s $(WORKING_DIR_CHANGES)

LD=%(LD)s
LDFLAGS=%(LDFLAGS)s
LIBS=%(LIBS)s

#-----
# Directory structure and setup.

# Directories containing source files.
VPATH=%(VPATH)s

# Directory for objects.
DEST=%(DEST)s

# Directory for compiled executables.
EXE=%(EXE)s

# We put compiled objects and modules in $(DEST).  If it doesn't exist, create it.
make_dest:=$(shell test -e $(DEST) || mkdir -p $(DEST))

# We put the compiled executable in $(EXE).  If it doesn't exist, then create it.
make_exe:=$(shell test -e $(EXE) || mkdir -p $(EXE))

PROG=%(PROGRAM)s

#-----
# VCS info.

# Get the version control id.  Git only.  Outputs a string.
VCS_VER:=$(shell set -o pipefail && echo -n \\" && ( git log --max-count=1 --pretty=format:%%H || echo -n 'Not under version control.' ) 2> /dev/null | tr -d '\\r\\n'  && echo -n \\")

# Test to see if the working directory contains changes.  Git only.  If the
# working directory contains changes (or is not under version control) then
# the _WORKING_DIR_CHANGES flag is set.
WORKING_DIR_CHANGES := $(shell git diff --quiet --cached && git diff --quiet 2> /dev/null || echo -n "-D_WORKING_DIR_CHANGES")

#-----
# Find source files and resultant object files.

# Source extensions.
EXTS = %(EXT)s

# Space separated list of source directories.
SRCDIRS := $(subst :, ,$(VPATH))

# Source filenames.
find_files = $(foreach ext,$(EXTS), $(wildcard $(dir)/*$(ext)))
SRCFILES := $(foreach dir,$(SRCDIRS),$(find_files))

# Objects (strip path and replace extension of source files with .o).
OBJ := $(addsuffix .o,$(basename $(notdir $(SRCFILES))))

# Full path to all objects.
OBJECTS := $(addprefix $(DEST)/, $(OBJ))

#-----
# Dependency file.

DEPEND = .depend

DEPEND_EXISTS := $(wildcard $(DEPEND))

# If the dependency file does not exist, then it is generated.  This 
# pass of make will not have the correct dependency knowledge though,
# so we force an exit.
ifneq ($(DEPEND_EXISTS),$(DEPEND))
\tTEST_DEPEND = no_depend
\tDEPEND_TARGET = $(DEPEND)
else
\tDEPEND_TARGET = depend_target
endif

#-----
# Compilation macros.

.SUFFIXES:
.SUFFIXES: $(EXTS)

# Files to be pre-processed then compiled.
$(DEST)/%%.o: %%.F90
\t$(FC) $(CPPDEFS) $(CPPFLAGS) -c $(FFLAGS) $< -o $@ %(MODULE_FLAG)s

# Files to compiled directly.
$(DEST)/%%.o: %%.f90
\t$(FC) -c $(FFLAGS) $< -o $@ %(MODULE_FLAG)s

#-----
# Goals.

.PHONY: clean test tests $(DEPEND_TARGET) depend help $(PROG) no_depend

# Compile program.
$(EXE)/$(PROG): $(TEST_DEPEND) $(OBJECTS)
\t$(MAKE) -B $(DEST)/environment_report.o
\ttest -e `dirname $@` || mkdir -p `dirname $@`
\t$(FC) -o $@ $(FFLAGS) $(LDFLAGS) -I $(DEST) $(OBJECTS) $(LIBS)

$(PROG): $(EXE)/$(PROG)

# Remove compiled objects and executable.
clean: 
\trm -f $(DEST)/*.{mod,o} $(EXE)/$(PROG)

# Build from scratch.
new: clean $(EXE)/$(PROG)

# Run tests.
test:
\tcd test_suite && testcode.py

tests: test

# Generate dependency file.
$(DEPEND_TARGET):
\ttools/sfmakedepend --file - --silent $(SRCFILES) --objdir \$$\(DEST\) --moddir \$$\(DEST\) > $(DEPEND)

depend: $(DEPEND_TARGET)

# Force exit if dependency file didn't exist as make didn't pickup the correct
# dependencies on this pass.
no_depend:
\t@echo "The required dependency file did not exist but has now been generated."
\t@echo "Please re-run make."
\texit 2

help:
\t@echo "Please use \`make <target>' where <target> is one of:"
\t@echo "  bin/hubbard.x        [default target] Compile program."
\t@echo "  hubbard.x            Compile program."
\t@echo "  clean                Remove the compiled objects."
\t@echo "  new                  Remove all previously compiled objects and re-compile."
\t@echo "  tests                Run test suite."
\t@echo "  test                 Run test suite."
\t@echo "  depend               Produce the .depend file containing the dependencies."
\t@echo "                       Requires the makedepf90 tool to be installed."
\t@echo "  help                 Print this help message."

#-----
# Include dependency file.

# $(DEPEND) will be generated if it doesn't exist.
include $(DEPEND)
'''

def create_makefile(config,debug=False):
    '''Create the Makefile for the desired config.  If debug is True, then the FFLAGS and LDFLAGS of the configuration are overwritten with the -g debug flag.'''
    if debug: config.update(FFLAGS='-g',LDFLAGS='-g')
    config.update(PROGRAM=program_name, DEST=dest, EXE=exe, VPATH=vpath, EXT=source_ext)
    f=open('Makefile','w')
    f.write(makefile_template % config)
    f.close()

if __name__=='__main__':
    args=sys.argv[1:]
    if '-d' in args or '--debug' in args:
        debug=True
        args=[arg for arg in args if (arg!='-d' and arg!='--debug')]
    else:
        debug=False
    if '-c' in args or '--config' in args:
        print 'Available configurations are:'
        for k,v in sorted(configurations.items()):
            print '\n%s' % k
            pprint.pprint(v)
        sys.exit()
    if '-h' in args or '--help' in args or len(args)!=1:
        print '%s\nAvailable configurations are: %s.' % (__doc__,', '.join(sorted(configurations.keys())))
        sys.exit()
    try:
        config=configurations[args[0]]
    except KeyError:
        print 'Configuration not recognized: %s' % args[0]
        print 'Available configurations are: %s.' % (', '.join(sorted(configurations.keys())))
        sys.exit()
    create_makefile(config,debug)
