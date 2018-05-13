from distutils.core import setup

setup(
    name='pyhande',
    version='0.1',
    author='HANDE developers',
    packages=('pyhande',),
    license='Modified BSD license',
    description='Analysis framework for HANDE calculations',
    long_description=open('README.rst').read(),
    install_requires=['numpy', 'scipy', 'pandas', 'pyblock', 'matplotlib'],
)
