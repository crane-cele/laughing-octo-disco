#!/usr/bin/env python
'''Run a reblocking analysis on HANDE QMC output files.  CCMC and FCIQMC
calculations only are supported.'''

import pandas as pd
from os import path
import sys
sys.path.append(path.join(path.abspath(path.dirname(sys.argv[0])), 'pyblock'))
import pyblock
import pyhande

import argparse

def run_hande_blocking(files, start_iteration, reblock_plot=None, verbose=1):
    '''Run a reblocking analysis on HANDE output and print to STDOUT.

See :func:`pyblock.pd_utils.reblock` and :func:`pyblock.blocking.reblock` for
details on the reblocking procedure.

Parameters
----------
files : list of list of strings
    names of files containing HANDE QMC calculation output.  Each list contains
    the a set of files which are analysed together (ie a series of calculations
    restarted from the previous calculation).
start_iteration : int
    QMC iteration from which statistics are gathered.
reblock_plot : string
    Filename to which the reblocking convergence plot (standard error vs reblock
    iteration) is saved.  The plot is not created if None and shown
    interactively if '-'.
verbose : int
    Level of verbosity.

    <0: print nothing
    0: print only the recommended statistics from the optimal block length.
    1: print blocking analysis and recommended statistics.
    2: print calculation metadata, blocking analysis and recommended statistics.

    If multiple independent calculations are analysed (i.e. len(files) > 1) then
    the first verbosity level is:

    0: print only the estimate from the optimal block length.

    and the value for levels 0-2 above are increased by 1.

Returns
-------
metadata : :class:`pandas.DataFrame`
    Metadata extracted from the calculation output file.
data : :class:`pandas.DataFrame`
    QMC data extracted from the calculation output file.
opt_block: :class:`pandas.DataFrame`
    Recommended statistics based upon the estimated 'optimal' block size
    as suggested by Wolff and Lee et al. (see
    :func:`pyblock.blocking.find_optimal_block`).
'''

    try:
        float_fmt = '{0:-#.8e}'.format
        float_fmt(1.0)
    except ValueError:
        # GAH.  Alternate formatting only added to format function after
        # python 2.6..
        float_fmt = '{0:-.8e}'.format

    # verbosity levels
    v_silent = -1
    if len(files) > 1:
        (v_estimate, v_rec_stats, v_analysis, v_meta, v_input) = (0, 1, 2, 3, 4)
    else:
        (v_rec_stats, v_analysis, v_meta, v_input) = (0, 1, 2, 3)

    infos = []
    for calc in files:
        info = pyhande.lazy.std_analysis(calc, start_iteration,
                                         extract_psips=True)
        if verbose >= v_analysis:
            print('Analysing file(s): %s' % (' '.join(calc)))
        if verbose >= v_meta:
            col_name = info.metadata.columns.name
            for (calc_name, calc) in info.metadata.iteritems():
                calc_local = calc.copy()
                # problems with pop on pandas 0.13?  It seems to return a list.
                calc_input = calc_local['input']
                calc_local = calc_local.drop('input')
                # Add the calc index to the series and make it come first.
                calc_local[col_name] = calc_name
                indx = calc_local.index.copy()
                indx = indx.delete(indx.get_loc(col_name)).insert(0, col_name)
                calc_local = calc_local.reindex(indx)
                print(calc_local.to_string(na_rep='n/a'))
                if verbose >= v_input:
                    print('\nFull input options:\n\n%s' % '\n'.join(calc_input))
                print('')
        if verbose >= v_analysis:
            print(info.reblock.to_string(float_format=float_fmt, line_width=90))
            print('')
        infos.append(info)

    opt_blocks = [info.opt_block for info in infos]
    if len(opt_blocks) == 1:
        opt_block = opt_blocks[0]
    else:
        if verbose < v_rec_stats:
            levels = ['mean', 'standard error', 'standard error error']
            for level in levels:
                opt_blocks = [opt_block.drop(level, axis=1)
                                for opt_block in opt_blocks
                                if level in opt_block]
        opt_blocks = [opt_block.stack() for opt_block in opt_blocks]
        indices = [','.join(calcs) for calcs in files]
        opt_block = pd.DataFrame(dict(zip(indices, opt_blocks))).T
        if verbose < v_rec_stats and not opt_block.empty:
            opt_block.columns = opt_block.columns.droplevel(1)

    if not opt_block.empty and verbose > v_silent:
        print('Recommended statistics from optimal block size:')
        print('')
        print(opt_block.to_string(float_format=float_fmt, na_rep='n/a',
                                  line_width=130))

    for (calc, info) in zip(files, infos):
        if info.no_opt_block and verbose > v_silent:
            fnames = ''
            if (len(files) > 1):
                fnames = ' in ' + ' '.join(calc)
            print('WARNING: could not find optimal block size%s.' % (fnames))
            print('Insufficient statistics collected for the following '
                  'variables: %s.' % (', '.join(info.no_opt_block)))

    if reblock_plot:
        for info in infos:
            pyblock.pd_utils.plot_reblocking(info.reblock, reblock_plot)

    return info

def parse_args(args):
    '''Parse command-line arguments.

Parameters
----------
args : list of strings
    command-line arguments.

Returns
-------
(filenames, start_iteration, reblock_plot)

where

filenames : list of strings
    list of QMC output files
start_iteration : int
    iteration number from which statistics should be gathered.
reblock_plot : string
    filename for the reblock convergence plot output.
'''

    parser = argparse.ArgumentParser(description = __doc__)
    parser.add_argument('-m', '--merge', default=False, action='store_true',
                        help='Combine data from each file before analysing. '
                        'Separate calculations can be denoted by placing \'--\''
                        ' between groups of files.  Default: treat each file as'
                        ' an independent calculation.')
    parser.add_argument('-p', '--plot', default=None, dest='plotfile',
                        help='Filename to which the reblocking convergence plot '
                        'is saved.  Use \'-\' to show plot interactively.  '
                        'Default: off.')
    parser.add_argument('-q', '--quiet', dest='verbose', action='store_const',
                        const=0, default=1,
                        help='Output only the final summary table.  '
                        'Overrides --verbose.')
    parser.add_argument('-s', '--start', type=int, dest='start_iteration',
                        default=0, help='Iteration number from which to gather '
                        'statistics.  Default: %(default)s.')
    parser.add_argument('-v', '--verbose', dest='verbose', action='count',
                        default=1, help='Increase verbosity of the output.  Can '
                        'be specified multiple times.')
    parser.add_argument('filenames', nargs=argparse.REMAINDER,
                        help='Space-separated list of files to analyse.')

    options = parser.parse_args(args)

    if not options.filenames:
        parser.print_help()
        sys.exit(1)

    if options.merge:
        merged = [[]]
        for fname in options.filenames:
            if fname == '--':
                if merged[-1]:
                    merged.append([])
            else:
                merged[-1].append(fname)
        options.filenames = merged
    else:
        options.filenames = [[fname] for fname in options.filenames]

    return (options.filenames, options.start_iteration, options.plotfile,
            options.verbose)

def main(args):
    '''Run reblocking and data analysis on HANDE output.

Parameters
----------
args : list of strings
    command-line arguments.

Returns
-------
None.
'''

    (files, start_iteration, reblock_plot, verbose) = parse_args(args)
    run_hande_blocking(files, start_iteration, reblock_plot, verbose)

if __name__ == '__main__':

    main(sys.argv[1:])
