/* Medical Aid transition study: SAS analysis workflow.
   Start with Run_Analysis.ps1, or set MA_DID_CODE to this directory.
   Source datasets are opened read-only. */
%macro locate_code;
  %global code_root;
  %let code_root=%qsysfunc(sysget(MA_DID_CODE));
  %if %length(%superq(code_root))=0 %then %do;
    %local entry;
    %let entry=%qsysfunc(sysget(SAS_EXECFILEPATH));
    %if %length(%superq(entry))=0 %then %let entry=%qsysfunc(getoption(sysin));
    %if %length(%superq(entry))>0 %then
      %let code_root=%qsysfunc(prxchange(s#[/\\][^/\\]+$##,1,%superq(entry)));
  %end;
  %if %length(%superq(code_root))=0 %then %do;
    %put ERROR: Cannot locate the code directory. Use Run_Analysis.ps1.;
    %abort cancel;
  %end;
%mend;
%locate_code;
%include "&code_root./00_config.sas";
%include "&code_root./01_utilities.sas";
%initialize;
%include "&code_root./02_build_panel.sas";
%guard(Build panel);
%include "&code_root./03_define_cohorts.sas";
%guard(Define cohorts);
%include "&code_root./04_match.sas";
%guard(Match baseline cohorts);
%include "&code_root./05_build_windows.sas";
%guard(Build follow-up windows);
%include "&code_root./06_models.sas";
%guard(Fit models);
%include "&code_root./07_reports.sas";
%guard(Export reports);
data out.workflow_complete;
  length status $32;
  status='COMPLETED_CHECK_MODEL_STATUS';
  completed_at=datetime();
  format completed_at datetime20.;
run;
%put NOTE: Workflow finished. Review model_status and balance diagnostics.;
