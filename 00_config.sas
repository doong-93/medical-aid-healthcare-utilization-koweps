/* All scientific choices are explicit. See ANALYSIS_PROTOCOL.md before use. */
%let first_year=2010;
%let last_year=2016;
%let controls_per_case=3;
%let ps_caliper=0.1; /* Absolute probability units, not 0.1 SD of the logit. */
%let match_seed=9342026;
%let age_offset=1;   /* Preserve the historical Korean-age convention. */
%let run_count_sensitivity=1;
%let raw_root=;
%macro load_local_settings;
%if %sysfunc(fileexist(%superq(code_root)/local_paths.sas)) %then %do;
  %include "&code_root./local_paths.sas";
%end;
%if %length(%qsysfunc(sysget(MA_DID_RAW)))>0 %then %let raw_root=%qsysfunc(sysget(MA_DID_RAW));
/* The launcher supplies a unique run identifier. */
%let run_id=%sysget(MA_DID_RUN);
%if %length(%superq(run_id))=0 %then
  %let run_id=run_%sysfunc(datetime(),hex16.);
%mend;
%global run_id;
%load_local_settings;
options validvarname=v7 mprint mlogic symbolgen nofmterr;
/* Do not suppress errors, format warnings, or convergence messages. */
