'''Attempt to remove population control bias by reweighting averages.'''

import pandas as pd
import numpy as np
from math import exp

def reweight(data, tstep, weight_itts, weight_key='Shift'):
    '''Reweight using population control to reduce population control bias.
See C. J. Umirigar et. al. J. Chem. Phys. 99, 2865 (1993) equations 14 ..., 20. 

Rewieght estimators linear in the number of psips by a factor:
    W(tau, N) = \\Pi^{N-1}_{m=0} e^{-\delta \\tau S(\\tau - m)}

Where S(\\tau - m) is the Shift on itteration \\tau - m,
\delta \\tau is the time step.
m is the number of itterations to reweight over.

Parameters
----------
data : :class:`pandas.DataFrame`
    HANDE QMC data.
tstep : float
    The time step used in the weight factor.
weight_itts: integer
    The number of iterations to reweight over.
weight_key: string
    Column to generate the reweighting data.

Returns
-------
data : :class:`pandas.DataFrame`
    HANDE QMC data. with weights appended
'''
    weights = []
    to_prod = np.exp(-tstep*data[weight_key])
    for i in range(len(data[weight_key])):
        if i-weight_itts > 0:
            weights.append(np.prod(to_prod[i-weight_itts:i]))
        else:
            weights.append(np.prod(to_prod[0:i-1]))

    data['Weight'] = weights

    return data
