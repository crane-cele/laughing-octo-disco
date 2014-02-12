'''Pandas-based wrapper around ``pyhande.blocking``.'''

import numpy
import matplotlib.pyplot as plt
import mpl_toolkits
import mpl_toolkits.axisartist as mpl_aa
import matplotlib.tight_layout as mpl_tl
import pandas as pd
import pyhande.blocking

def reblock(data, axis=0):
    '''Blocking analysis of correlated data.

Parameters
----------
data: pandas.Series or pandas.DataFrame
    Data to be blocked.  See ``axis`` for order.
axis:
    If non-zero, variables in data are in rows with the columns
    corresponding to the observation values.  Blocking is the performed along
    the rows.  Otherwise each column is a variable, the observations are in the
    columns and blocking is performed down the columns.  Only used if data is
    a pandas.DataFrame.

Returns
-------
block_data: pandas.DataFrame
    Mean, standard error and estimated standard error for each variable at each
    reblock step.
covariance: pandas.DataFrame
    Covariance matrix at each reblock step.

See also
--------
``pyhande.blocking.reblock``: numpy-based implementation.

``pyhande.pd_utils.reblock`` is a simple wrapper around the numpy-based
implementation.  See there for documentation about the reblocking procedure.
'''

    try:
        columns = [data.name]
        axis = 0
    except AttributeError:
        # Have DataFrame rather than Series.
        if axis:
            columns = data.index.values
        else:
            columns = data.columns.values

    block_stats = pyhande.blocking.reblock(data.values, rowvar=axis)
    data_size = data.shape[axis]
    optimal_blocks = pyhande.blocking.find_optimal_block(data_size, block_stats)

    # Now nicely package it up into a dict of pandas/built-in objects.

    iblock = []
    block_info = []
    covariance = []
    keys = ['mean', 'standard error', 'standard error error', 'optimal block']
    multi_keys = [(col,k) for col in columns for k in keys]
    multi_keys = pd.MultiIndex.from_tuples(multi_keys)
    null = [0]*len(columns)
    for stat in block_stats:
        # (iblock, mean, covariance, standard err, error on standard error)
        iblock.append(stat[0])

        pd_stat = numpy.array([stat[1], stat[3], stat[4], null]).T.flatten()
        block_info.append(pd.Series(pd_stat, index=multi_keys))

        # Covariance is a 2D matrix (in general) so can't put it into
        # a DataFrame with everything else, so put it in its own.
        cov = numpy.array(stat[2], ndmin=2)
        covariance.append(pd.DataFrame(cov, index=columns, columns=columns))

    block_info = pd.concat(block_info, axis=1, keys=iblock).transpose()
    block_info.index.name = 'reblock'
    loc = block_info.columns.get_level_values(1) == 'optimal block'
    block_info.loc[:,loc] = ''

    covariance = pd.concat(covariance, keys=iblock)
    covariance.index.names = ['reblock', '']

    for (ivar, optimal) in enumerate(optimal_blocks):
        if optimal >= 0:
            block_info.loc[optimal,(columns[ivar], 'optimal block')] = '<---    '

    return (block_info, covariance)

def plot_reblocking(block_info, plotfile=None, plotshow=True):
    '''Plot the reblocking data.

Parameters
----------
block_info: pandas.DataFrame
    Reblocking data (i.e. the first item of the tuple returned by ``reblock``).
plotfile: string
    If not null, save the plot to the given filename.  If '-', then show the
    plot interactively.  See also ``plotshow``.
plotshow: bool
    If ``plotfile`` is not given or is '-', then show the plot interactively.

Returns
-------
matplotlib.figure.Figure
    plot of the reblocking data.
'''

    # See http://matplotlib.org/examples/axes_grid/demo_parasite_axes2.html.

    # Create host axes.  Must plot to here first and then clone...
    fig = plt.figure()
    host = mpl_toolkits.axes_grid1.host_subplot(111, axes_class=mpl_aa.Axes)
    print('host', type(host))

    offset = -90 # distance between y axes.
    axes = []
    for (i, col) in enumerate(block_info.columns.get_level_values(0).unique()):
        if i == 0:
            ax = host
        else:
            ax = host.twinx()
            # Create a new y axis a little to the left of the current figure.
            new_fixed_axis = ax.get_grid_helper().new_fixed_axis
            ax.axis["left"] = new_fixed_axis(loc='left', axes=ax,
                                             offset=(i*offset,0))
            # Hide right-hand side ticks as the multiple y axes just interfere
            # with each other.
            ax.axis["right"].toggle(all=False)

        block = block_info.index.values
        std_err = block_info.ix[:,(col, 'standard error')].values
        std_err_err = block_info.ix[:,(col, 'standard error error')].values
        line = ax.errorbar(block, std_err, std_err_err, marker='o', label=col)

        # There should only be (at most) one non-null value for optimal block.
        opt = block_info.loc[:,(col, 'optimal block')]
        opt = opt.ix[opt != ''].index.values
        if opt:
            opt = opt[0]
            ax.annotate('', (block[opt], std_err[opt]-std_err_err[opt]), 
                         xytext=(0, -30), textcoords='offset points', 
                         arrowprops=dict(
                             arrowstyle="->", color=line[0].get_color()
                       ),)

        ax.set_ylabel('%s standard error' % col, labelpad=0)
        ax.set_xlim((-0.1,len(block)-0.9))
        axes.append(ax)

    plt.xlabel('Reblock iteration')
    plt.legend(loc=2)

    plt.tight_layout()

    if plotfile == '-' or (not plotfile and plotshow):
        plt.show()
    else:
        plt.savefig(plotfile)

    return fig
