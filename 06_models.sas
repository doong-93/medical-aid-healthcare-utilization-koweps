/* Primary estimand: absolute change in mean annual utilization/spending in
   matched stable switchers relative to matched observed NHI-only controls.
   The did coefficient is an additive difference-in-differences contrast.
   Event cohort fixed effects account for baseline level differences.
   These models do not establish identification or validate parallel trends. */
%macro record_model(type,w,outcome,model,status);
  data work.status_row;
    length aid_type window 8 outcome $32 model $24 status $64;
    aid_type=&type.; window=&w.; outcome="&outcome."; model="&model."; status="&status.";
  run;
  proc append base=out.model_status data=work.status_row; run;
%mend;

%macro fit_model(type,w,y,index,kind,distribution,link);
  %local n clusters miny maxy cells stem fitstatus badconv badestimate;
  %let stem=m&type._&w._&index._&kind.;
  proc sql noprint;
    select count(*),count(distinct household_lineage),min(&y.),max(&y.)
      into :n trimmed,:clusters trimmed,:miny trimmed,:maxy trimmed from work.model_data;
    select count(distinct cats(treated,post)) into :cells trimmed from work.model_data;
  quit;
  %if &n.=0 or &clusters.<2 or &cells.<4 %then %do;
    %record_model(&type.,&w.,&y.,&kind.,SKIPPED_INSUFFICIENT_DATA);
    %return;
  %end;
  %if %sysevalf(&miny.=&maxy.) %then %do;
    %record_model(&type.,&w.,&y.,&kind.,SKIPPED_CONSTANT_OUTCOME);
    %return;
  %end;
  ods output GEEEmpPEst=out.&stem._parameters
    Estimates=out.&stem._estimate ConvergenceStatus=out.&stem._convergence;
  proc genmod data=work.model_data;
    class household_lineage event_year;
    model &y.=event_year treated post did / dist=&distribution. link=&link.;
    repeated subject=household_lineage / type=ind;
    estimate 'Treatment-by-post interaction' did 1;
    output out=out.&stem._predicted(keep=person_id survey_year household_lineage
      treated post &y. predicted) pred=predicted;
  run;
  ods output close;
  %guard(GEE model &stem.);
  %let fitstatus=REVIEW_LOG_AND_CONVERGENCE;
  %if %sysfunc(exist(out.&stem._convergence)) and %sysfunc(exist(out.&stem._estimate)) %then %do;
    proc sql noprint;
      select sum(status ne 0) into :badconv trimmed from out.&stem._convergence;
      select sum(missing(LBetaEstimate) or missing(StdErr)) into :badestimate trimmed
        from out.&stem._estimate;
    quit;
    %if &badconv.=0 and &badestimate.=0 %then %let fitstatus=CONVERGED_REVIEW_DIAGNOSTICS;
    %else %let fitstatus=NOT_CONVERGED_OR_NOT_ESTIMABLE;
  %end;
  %if &clusters.<30 %then %let fitstatus=&fitstatus._FEW_CLUSTERS;
  %record_model(&type.,&w.,&y.,&kind.,&fitstatus.);
%mend;

%macro pretrend(type,w,y,index);
  %local nclusters nrows stem;
  %let stem=pre&type._&w._&index.;
  data work.pre_data;
    set work.model_data;
    if relative_time<0;
    treated_pretrend=treated*relative_time;
  run;
  proc sql noprint;
    select count(*),count(distinct household_lineage) into :nrows trimmed,:nclusters trimmed
    from work.pre_data;
  quit;
  %if &nrows.=0 or &nclusters.<2 %then %return;
  ods output GEEEmpPEst=out.&stem._parameters Estimates=out.&stem._estimate
    ConvergenceStatus=out.&stem._convergence;
  proc genmod data=work.pre_data;
    class household_lineage event_year;
    model &y.=event_year treated relative_time treated_pretrend / dist=normal link=identity;
    repeated subject=household_lineage / type=ind;
    estimate 'Pre-period difference in annual slopes' treated_pretrend 1;
  run;
  ods output close;
  %guard(Pre-period trend diagnostic);
%mend;

%macro all_models;
  %local t w i y;
  %do t=1 %to 2;
    %do w=1 %to 3;
      proc sort data=out.analysis_panel(where=(aid_type=&t. and window=&w.))
        out=work.model_data;
        by household_lineage person_id survey_year;
      run;
      %do i=1 %to 3;
        %let y=%scan(outpatient inpatient_days household_cost_usd,&i.);
        %fit_model(&t.,&w.,&y.,&i.,additive,normal,identity);
        %if &run_count_sensitivity.=1 and &i.<3 %then
          %fit_model(&t.,&w.,&y.,&i.,nb,negbin,log);
        %if &w.>=2 %then %pretrend(&t.,&w.,&y.,&i.);
      %end;
    %end;
  %end;
%mend;
%all_models;
/* exp(did) from a log-link model is a ratio of mean ratios, not a difference
   in visits/days. No zero-inflated model is fitted to continuous spending. */
