/* Propensity score matching uses PROC PSMATCH.
   Cases and controls are scored at g-1, separately for MA type, with event-year
   indicators. Matching is restricted to the same event year.
   Controls are not reused across event cohorts within the same MA analysis. */
%let ps_class=sex region married employed age_group income_group health;
%let ps_cont=private_count private_premium;

data out.matched_people;
  length person_id household_lineage aid_type event_year treated match_set ps 8;
  stop;
run;
data out.matching_status;
  length aid_type event_year candidates cases controls matched_cases matched_controls 8 status $64;
  stop;
run;

%macro prepare_scores(type);
  %local cases badcon;
  %global scores_ready_&type.;
  %let scores_ready_&type.=0;
  proc sql;
    create table work.case_baselines as
    select p.*,1 as treated,e.aid_type,e.event_year
    from out.panel as p inner join out.eligible_cases as e on p.person_id=e.person_id
    where e.aid_type=&type. and p.survey_year=e.event_year-1 and p.baseline_complete=1;
    create table work.event_cohorts as
    select distinct event_year from work.case_baselines;
    create table work.pooled_candidates as
    select * from work.case_baselines
    union all corr
    select p.*,0 as treated,&type. as aid_type,g.event_year
    from out.panel as p inner join out.eligible_controls as c on p.person_id=c.person_id
    inner join work.event_cohorts as g on p.survey_year=g.event_year-1
    where p.baseline_complete=1;
    select count(*) into :cases trimmed from work.case_baselines;
  quit;
  %if &cases.=0 %then %return;
  %unique(work.pooled_candidates,%str(person_id,event_year),out.duplicate_ps_candidates);
  proc sort data=work.pooled_candidates; by event_year person_id; run;
  /* Pool event cohorts to avoid fitting a full covariate model to one or two
     switchers in a year. The same control may enter multiple baseline risk
     sets during score estimation, but is matched only once within MA type. */
  proc datasets lib=work nolist; delete ps_convergence ps_scored; quit;
  ods output ConvergenceStatus=work.ps_convergence;
  proc logistic data=work.pooled_candidates;
    class event_year &ps_class. / param=ref;
    model treated(event='1')=event_year &ps_class. &ps_cont.;
    output out=work.ps_scored pred=ps;
  run;
  ods output close;
  %guard(Propensity score estimation);
  %if not %sysfunc(exist(work.ps_convergence)) %then
    %fail(No propensity score convergence status was produced);
  data out.ps_convergence_&type.; set work.ps_convergence; run;
  data out.pooled_ps_&type.; set work.ps_scored; run;
  proc sql noprint;
    select sum(status ne 0) into :badcon trimmed from work.ps_convergence;
  quit;
  %if &badcon.=0 %then %let scores_ready_&type.=1;
%mend;

%macro match_cohort(type,g);
  %local nc nt ncontrols nsets nmatched cohort_status;
  %let nc=0; %let nt=0; %let ncontrols=0; %let nsets=0; %let nmatched=0;
  %let cohort_status=PS_UNAVAILABLE_OR_NOT_CONVERGED;
  %if &&scores_ready_&type.=1 %then %do;
  proc sql;
    create table work.risk_set as
    select p.* from out.pooled_ps_&type. as p
    where p.event_year=&g.
      and not exists (select * from out.matched_people as m
        where m.aid_type=&type. and m.person_id=p.person_id);
    select count(*),sum(treated=1),sum(treated=0) into :nc trimmed,:nt trimmed,:ncontrols trimmed
      from work.risk_set;
  quit;
  proc sort data=work.risk_set; by treated person_id; run;
  %if &nc.=0 %then %do; %let nt=0; %let ncontrols=0; %end;
  %let nsets=0; %let nmatched=0;
  %let cohort_status=INSUFFICIENT_CANDIDATES;
  data out.ps_candidates_&type._&g.; set work.risk_set; run;
  %if &nt.>0 and &ncontrols.>=&controls_per_case. %then %do;
      proc datasets lib=work nolist; delete matched_raw; quit;
      proc psmatch data=work.risk_set region=allobs;
        class treated;
        psdata treatvar=treated(treated='1') ps=ps;
        match method=greedy(k=&controls_per_case. order=random(seed=&match_seed.))
          stat=ps caliper(mult=one)=&ps_caliper.;
        output out(obs=match)=work.matched_raw matchid=local_set;
      run;
      %guard(Nearest-neighbor matching);
      %if not %sysfunc(exist(work.matched_raw)) %then %fail(PSMATCH produced no dataset);
      /* Keep complete 1:K sets. A partially matched case is not counted as 1:K. */
      proc sql;
        create table work.complete_sets as
        select local_set from work.matched_raw where not missing(local_set)
        group by local_set
        having sum(treated=1)=1 and sum(treated=0)=&controls_per_case.;
        create table work.accepted as
        select p.*,&type.*100000000+&g.*10000+p.local_set as match_set
        from work.matched_raw as p inner join work.complete_sets as s
        on p.local_set=s.local_set;
        select count(*) into :nsets trimmed from work.complete_sets;
        select count(*) into :nmatched trimmed from work.accepted where treated=0;
      quit;
      data work.append_match;
        set work.accepted;
        keep person_id household_lineage aid_type event_year treated match_set ps;
      run;
      proc append base=out.matched_people data=work.append_match; run;
      %let cohort_status=MATCHED;
      %if &nsets.=0 %then %let cohort_status=NO_COMPLETE_MATCH_SETS;
  %end;
  %end;
  data work.match_status_row;
    length status $64;
    aid_type=&type.; event_year=&g.; candidates=&nc.; cases=&nt.; controls=&ncontrols.;
    matched_cases=&nsets.; matched_controls=&nmatched.; status="&cohort_status.";
  run;
  proc append base=out.matching_status data=work.match_status_row; run;
%mend;

%macro all_matching;
  %local t g;
  %do t=1 %to 2;
    %prepare_scores(&t.);
    %do g=%eval(&first_year.+1) %to &last_year.;
      %match_cohort(&t.,&g.);
    %end;
  %end;
%mend;
%all_matching;
%unique(out.matched_people,%str(aid_type,person_id),out.duplicate_matched_people);
proc sql;
  create table out.match_caliper_check as
  select aid_type,match_set, count(*) as members,
    max(ps)-min(ps) as total_ps_range,
    max(case when treated=1 then ps else . end) as case_ps,
    max(case when treated=0 then ps else . end) as max_control_ps,
    min(case when treated=0 then ps else . end) as min_control_ps
  from out.matched_people group by aid_type,match_set;
quit;
data out.bad_calipers;
  set out.match_caliper_check;
  if max(abs(case_ps-max_control_ps),abs(case_ps-min_control_ps))>&ps_caliper.+1e-10;
run;
%assert_empty(out.bad_calipers,An accepted match exceeds the absolute PS caliper);
