"""Extract and merge (meta)data from (multiple) HANDE output files."""
from typing import Dict, List, Union
import copy
import warnings
import math
import pandas as pd
import pyhande.extract as extract
from pyhande.extracting.abs_extractor import AbsExtractor
from pyhande.helpers.simple_callables import do_nothing, RaiseValueError


class Extractor(AbsExtractor):
    """Extract data/metadata from HANDE output files and merge.

    Merge if desired/sensible, e.g. when calculation was restarted.
    This expands the functionality of extract.py and is more compactly
    represented as a class.
    """

    def __init__(
            self,
            merge: Dict[str, Union[List[str], str]] = None) -> None:
        """
        Initialise instance.

        Parameters
        ----------
        merge : Dict[str, Union[List[str], str]], optional
            Allow partial declaration, rest will be defaults.
            merge['type']: str
                * 'uuid': Do merge based on UUIDs of calculations.
                    Restarted calculation has UUID of calculation
                    restarted from in metadata. `out_files` do not need
                    to be ordered in that case. Default.
                * 'legacy': Do merge if iterations in consecutive
                    calculations in `out_files` are consecutive. Order
                    in `out_files` matters therefore. Mainly here for
                    legacy reasons when restart UUID was not saved in
                    metadata yet.
                * 'no': Don't merge.
                    Treat calculations in different files in `out_files`
                    as separate calculations.
            merge['md_always']: List[str]
                Only merge if metadata listed here is same.
                The default is ['qmc:tau'].
            merge['md_shift']: List[str]
                Only merge if metadata listed here is the same if
                `Shift`, as determined by `merge['shift_key']` has
                already started varying. If shift is not varying,
                ignore this metadata.
                The default is [].
            merge['shift_key']: str
                Column name of `Shift` which, if varying decided
                merging if metadata in `merge['md_shift']` is different.
                The default is 'Shift'.
            merge['it_key']: str
                Column name of iterations which, if
                merge['type'] == 'legacy', is used to check whether a
                calculation is the continuation of another for merging.
                The default is 'iterations'.
        """
        self._merge: Dict[str, Union[List[str], str]]
        self._set_merge(merge)
        self._not_extracted_message: str = (
            '(Meta)Data has not been extracted yet. Use the ".exe" method to '
            'start extracting.')
        # The following will be set later (by "exe" attribute method):
        self._data: List[pd.DataFrame]
        self._metadata: List[List[Dict]]
        self._all_ccmc_fciqmc: bool
        self._calc_to_outfile_ind: List[List[int]]

    def _set_merge(self, merge):
        """Set and check input for merge parameter."""
        # First set to default.
        self._merge = {
            'type': 'uuid', 'md_always': ['qmc:tau'], 'md_shift': [],
            'shift_key': 'Shift', 'it_key': 'iterations'
        }
        # Now update default with user's specifications.
        if merge:
            if any([merge_key not in self._merge.keys() for merge_key in
                    merge.keys()]):
                raise ValueError(f"Not all {merge.keys()} in passed 'merge' "
                                 f"dictionary are in {self._merge.keys()}.")
            self._merge.update(merge)
        # In case user has passed strings instead of list of strings.
        if isinstance(self._merge['md_always'], str):
            self._merge['md_always'] = [self._merge['md_always']]
        if isinstance(self._merge['md_shift'], str):
            self._merge['md_shift'] = [self._merge['md_shift']]

    @property
    def out_files(self) -> List[str]:
        """
        Access (read only) out_files property.

        Raises
        ------
        AttributeError
            If data has not been extracted yet, i.e. output files have
            not been passed yet.

        Returns
        -------
        List[str]
            List of `out_files` names the data is extracted from.
        """
        try:
            return self._out_files
        except AttributeError:
            print(self._not_extracted_message)
            raise

    @property
    def data(self) -> List[pd.DataFrame]:
        """
        Access (extracted) data property.

        Raises
        ------
        AttributeError
            If data has not been extracted yet.

        Returns
        -------
        List[pd.DataFrame]
            QMC Data.
            List over merged calculations.
        """
        try:
            return self._data
        except AttributeError:
            print(self._not_extracted_message)
            raise

    @property
    def metadata(self) -> List[List[Dict]]:
        """
        Access (extracted) metadata property.

        Raises
        ------
        AttributeError
            If metadata has not been extracted yet.

        Returns
        -------
        List[List[Dict]]
            Metadata.
            List over merged calculations where each element is a list
            over the metadata of the calculations that got merged.
        """
        try:
            return self._metadata
        except AttributeError:
            print(self._not_extracted_message)
            raise

    @property
    def calc_to_outfile_ind(self) -> List[List[int]]:
        """
        Map index of calculation to output file.

        This maps what HANDE output file the data and metadata belong
        to. E.g. [[0], [0], [1, 2]] with three output files shows that
        the first calculations (index 0) contained two calculations and
        the second and third output file (indices 1 and 2) were merged
        to the third calculation.

        Raises
        ------
        AttributeError
            If data has not been extracted yet.

        Returns
        -------
        List[List[int]]
            Outer list has length equal the length of the data/metadata
            lists and contains list of indices of output files
            containing them (see above).
        """
        try:
            return self._calc_to_outfile_ind
        except AttributeError:
            print(self._not_extracted_message)
            raise

    @property
    def all_ccmc_fciqmc(self) -> bool:
        """
        Are all calculations extracted either CCMC or FCIQMC.

        This will affect what postprocessing can be done.

        Raises
        ------
        AttributeError
            If data has not been extracted yet.

        Returns
        -------
        bool
            True if all calculations extracted are either CCMC or
            FCIQMC. False if at least one is of another type, such as
            FCI or Hilbert space estimation.

        """
        try:
            return self._all_ccmc_fciqmc
        except AttributeError:
            print(self._not_extracted_message)
            raise

    @staticmethod
    def _is_equal_value(one, two):
        """Test whether two objects (assumed same type) are equal."""
        # [todo] what with lists containing floats?
        if isinstance(one, float):
            return math.isclose(one, two)
        return one == two

    def _merge_safe(
            self, i_child: int, i_parent: int) -> bool:
        """
        Test whether merge is safe to do given metadata of the calcs.

        Parameters
        ----------
        i_child : int
            Index of child/restarted calculation in e.g. self.data.
        i_parent : int
            Index of parent/older calculation in e.g. self.data.

        Returns
        -------
        bool
        True if merge is safe given metadata, False if not.
        """
        meta_to_consider = copy.copy(self._merge['md_always'])
        if (self._merge['md_shift'] and
                (self._data[i_child].loc[0, self._merge['shift_key']] !=
                 self._data[i_parent].loc[0, self._merge['shift_key']])):
            # Assume that checking one shift value in parent is enough!
            meta_to_consider += self._merge['md_shift']
        for meta in meta_to_consider:
            md_child = self.metadata[i_child][0]
            md_parent = self.metadata[i_parent][-1]
            for meta_key in meta.split(':'):
                try:
                    md_child = md_child[meta_key]
                    md_parent = md_parent[meta_key]
                except KeyError:
                    if meta in self._merge['md_always']:
                        to_fix = "merge['md_always']"
                    else:
                        to_fix = "merge['md_shift']"
                    print(f"Metadata does not contain {meta}! Fix '{to_fix}'!")
                    raise
            if not self._is_equal_value(md_child, md_parent):
                warnings.warn(f"Not merging some calcs because metadata {meta} "
                              "differs.")
                return False
        return True

    def _do_merge(self, i_child: int, i_parent: int):
        """
        Merge two calculations.

        Dataframes in data are concatenated, list of metadata is
        extended and calc_to_outfile_ind list is also extended.

        Parameters
        ----------
        i_child : int
            Index of child/restarted calculation in e.g. self.data.
        i_parent : int
            Index of parent/older calculation in e.g. self.data.
        """
        # Note that i_parent == i_child is not possible.
        # Index of parent calculation has to be reduced by -1 if child
        # calculation comes before it and is removed.
        add_to_index = i_parent if i_parent < i_child else i_parent - 1
        parent_data = self._data[i_parent]
        child_data = self._data.pop(i_child)
        self._data[add_to_index] = pd.concat([parent_data, child_data],
                                             ignore_index=True)
        child_metadata = self._metadata.pop(i_child)
        self._metadata[add_to_index].extend(child_metadata)
        child_calc_to_outfile_ind = self._calc_to_outfile_ind.pop(i_child)
        self._calc_to_outfile_ind[add_to_index].extend(
            child_calc_to_outfile_ind)

    def _merge_uuid(self):
        """Attempt merging using UUIDs.

        Calculations are potentially merged, using UUID info.
        Order of calcs not important.
        """
        i_child = 0
        while i_child < len(self._data):
            merged = False
            if 'uuid_restart' in self.metadata[i_child][0]['restart']:
                uuid_r = self.metadata[i_child][0]['restart']['uuid_restart']
                for i_parent in range(len(self.data)):
                    if (uuid_r == self.metadata[i_parent][-1]['UUID']
                            and self._merge_safe(i_child, i_parent)):
                        self._do_merge(i_child, i_parent)
                        merged = True
                        break
            if not merged:
                i_child += 1

    def _merge_legacy(self):
        """Attempt merging checking continuation of iterations.

        Only adjacent calcs can be merged!
        """
        i_child = 1  # Note order matters so start with second.
        while i_child < len(self._data):
            ncycles = (self.data[i_child][self._merge['it_key']].iloc[1]
                       - self.data[i_child][self._merge['it_key']].iloc[0])
            if ((self.data[i_child][self._merge['it_key']].iloc[0] - ncycles ==
                 self.data[i_child-1][self._merge['it_key']].iloc[-1])
                    and self._merge_safe(i_child, i_child - 1)):
                self._do_merge(i_child, i_child - 1)
            else:
                i_child += 1

    def exe(self, out_files: List[str]):
        """Extract and merge.

        The merge code was inspired by an older implementation in
        deprecated/removed lazy.py file.
        [todo] Test with calc where a file has more then one calc.

        Parameters
        ----------
        out_files : List[str]
            List of HANDE output filenames to be extracted here.
        """
        self._out_files: List[str] = out_files

        # Extract.
        self._metadata, self._data, self._calc_to_outfile_ind = map(
            list, zip(*[
                [[md], dat, [i]]
                for i, out_file in enumerate(self._out_files)
                for (md, dat) in extract.extract_data(out_file)
            ]))

        # Merging?
        # Are all calculations either CCMC or FCIQMC?  Only then we merge.
        calc_types = [md[0]['calc_type'] for md in self.metadata]
        self._all_ccmc_fciqmc = all(
            [ct in ['FCIQMC', 'CCMC'] for ct in calc_types])
        if self._all_ccmc_fciqmc:
            select_merge_func = {
                'uuid': self._merge_uuid, 'legacy': self._merge_legacy,
                'no': do_nothing
            }
            select_merge_func.get(
                self._merge['type'],
                RaiseValueError("Invalid merge value in 'merge['type']': "
                                f"'{self._merge['type']}'. Choose from "
                                f"'{select_merge_func.keys()}'"))()
