#!/usr/bin/python
'''reblock_hande.py [options] file_1 file_2 ... file_N

Run a reblocking analysis on HANDE QMC output files.  CCMC and FCIQMC
calculations only are supported.'''

import pandas as pd
import pyhande
import sys

# Still supporting 2.6.  *sigh*
import optparse

def run_hande_blocking(files, start_iteration, reblock_plot=None):
    '''Run a reblocking analysis on HANDE output and print to STDOUT.

See ``pyhande.pd_utils.reblock`` and ``pyhande.blocking.reblock`` for details on
the reblocking procedure.

Parameters
----------
files: list of strings
    names of files containing HANDE QMC calculation output.
start_iteration: int
    QMC iteration from which statistics are gathered.
reblock_plot: string
    Filename to which the reblocking convergence plot (standard error vs reblock
    iteration) is saved.  The plot is not created if None and shown
    interactively if '-'.

Returns
-------
None.
'''

    float_fmt = '{0:-#.8e}'.format
    data = pyhande.extract.extract_data_sets(files)

    # Reblock over desired window.
    indx = data['iterations'] >= start_iteration
    mc_data =  data.ix[indx, ['Instant shift', '\sum H_0j Nj', '# D0']]
    (data_length, reblock, covariance) = pyhande.pd_utils.reblock(mc_data)

    # Calculate projected energy.
    proje_sum = reblock.ix[:, '\sum H_0j Nj']
    ref_pop = reblock.ix[:, '# D0']
    proje_ref_cov = covariance.xs('# D0', level=1)['\sum H_0j Nj']
    proje = pyhande.error.ratio(proje_sum, ref_pop, proje_ref_cov, data_length)

    print(reblock.to_string(float_format=float_fmt, line_width=80))

    # Data summary: suggested data to use from reblocking analysis.
    opt_data = []
    no_opt = []
    for col in ('Instant shift', '\sum H_0j Nj', '# D0'):
        summary = pyhande.pd_utils.reblock_summary(reblock.ix[:, col])
        if summary.empty:
            no_opt.append(col)
        else:
            summary.index = [col]
        opt_data.append(summary)
    summary = pyhande.pd_utils.reblock_summary(proje)
    if summary.empty:
        no_opt.append('Proj. Energy')
    else:
        summary.index = ['Proj. Energy']
    opt_data.append(summary)
    opt_data = pd.concat(opt_data)
    if not opt_data.empty:
        print()
        print('Recommended statistics from optimal block size:')
        print()
        print(opt_data.to_string(float_format=float_fmt))
    if no_opt:
        print()
        print('WARNING: could not find optimal block size.')
        print('Insufficient statistics collected for the following variables: '
              '%s.' % (', '.join(no_opt)))

    if reblock_plot:
        pyhande.pd_utils.plot_reblocking(reblock, reblock_plot)

def parse_args(args):
    '''Parse command-line arguments.

Parameters
----------
args: list of strings
    command-line arguments.

Returns
-------
(filenames, start_iteration, reblock_plot)

where

filenames: list of strings
    list of QMC output files
start_iteration: int
    iteration number from which statistics should be gathered.
reblock_plot: string
    filename for the reblock convergence plot output.
'''

    parser = optparse.OptionParser(usage = __doc__)
    parser.add_option('-p', '--plot', default=None, dest='plotfile',
                      help='Filename to which the reblocking convergence plot '
                      'is saved.  Use \'-\' to show plot interactively.  '
                      'Default: off.')
    parser.add_option('-s', '--start', type='int', dest='start_iteration',
                      default=0, help='Iteration number from which to gather '
                           'statistics.  Default: %default.')

    (options, filenames) = parser.parse_args(args)

    if not filenames:
        parser.print_help()
        sys.exit(1)

    return (filenames, options.start_iteration, options.plotfile)

def main(args):
    '''Run reblocking and data analysis on HANDE output.

Parameters
----------
args: list of strings
    command-line arguments.

Returns
-------
None.
'''

    (files, start_iteration, reblock_plot) = parse_args(args)
    run_hande_blocking(files, start_iteration, reblock_plot)

if __name__ == '__main__':

    main(sys.argv[1:])
