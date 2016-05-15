#!/usr/bin/env python

import numpy
import sys
import os

try:
    import matplotlib.pyplot as plt
    USE_MATPLOTLIB = True
except ImportError:
    USE_MATPLOTLIB = False

if not pkgutil.find_loader('pyhande'):
    _script_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.append(os.path.join(_script_dir, '../pyhande'))
import pyhande

def finite_temp_energy(beta, spectrum):

    s1 = 0.0
    s2 = 0.0
    for eigv in spectrum:
        e = numpy.exp(-beta*eigv)
        s1 += e*eigv
        s2 += e
    return s1/s2


def propogate_spectrum(beta_min, beta_max, nbeta, spectrum):

    beta = numpy.arange(beta_min, beta_max, float(beta_max-beta_min)/(nbeta-1))

    energies = [finite_temp_energy(b, spectrum) for b in beta]

    print('#     beta             E(beta)')
    for i in range(len(beta)):
        print('%16.8f %16.8f' % (beta[i], energies[i]))

    if USE_MATPLOTLIB:
        plt.plot(beta, energies)
        plt.show()

if __name__ == '__main__':

    if len(sys.argv) != 5:
        print('Usage:', sys.argv[0], 'fci_file beta_min beta_max nbeta')
        print(r'Evaluate E(\beta) from the output of an FCI calculation '
              'contained in fci_file produced by HANDE, between beta_min '
              'and beta_max in steps of (beta_max-beta_min)/(nbeta-1).')
        sys.exit(1)

    (fci_file, beta_min, beta_max, nbeta) = sys.argv[1:]
    beta_min = float(beta_min)
    beta_max = float(beta_max)
    nbeta = float(nbeta)

    spectrum = None
    for (md, calc) in pyhande.extract.extract_data(fci_file):
        print md, calc
        if md['calc_type'] == 'FCI':
            spectrum = calc
            break
    if spectrum is None:
        raise RuntimeError('%s does not contain an FCI calculation.'%(fci_file))

    propogate_spectrum(beta_min, beta_max, nbeta, spectrum)
