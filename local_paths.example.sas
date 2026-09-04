/* Copy to local_paths.sas when configuring another computer.
   Keep macro quoting if the directory contains semicolons or other symbols. */
%let raw_root=%nrstr(C:/Research/medical-aid/raw);
