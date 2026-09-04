/* Balance is assessed for every categorical level, not by treating category
   codes as a continuous score. Before-match SDs are held fixed across stages. */
%macro collect_balance;
  %local t g;
  data work.balance_input;
    length aid_type event_year treated window ps sex region married employed age_group
      income_group health private_count private_premium 8 stage $12;
    stop;
  run;
  %do t=1 %to 2;
    %do g=%eval(&first_year.+1) %to &last_year.;
      %if %sysfunc(exist(out.ps_candidates_&t._&g.)) %then %do;
        data work.before;
          set out.ps_candidates_&t._&g.;
          stage='Before'; window=0;
          keep aid_type event_year treated window ps sex region married employed age_group
            income_group health private_count private_premium stage;
        run;
        proc append base=work.balance_input data=work.before; run;
      %end;
    %end;
  %end;
  proc sql;
    create table work.after as
    select m.aid_type,m.event_year,m.treated,0 as window,m.ps,
      p.sex,p.region,p.married,p.employed,p.age_group,p.income_group,p.health,
      p.private_count,p.private_premium,'After' as stage length=12
    from out.matched_people as m inner join out.panel as p
    on m.person_id=p.person_id and p.survey_year=m.event_year-1;
    create table work.final_baselines as
    select distinct aid_type,match_set,window from out.analysis_panel;
    create table work.final_balance as
    select m.aid_type,m.event_year,m.treated,f.window,m.ps,
      p.sex,p.region,p.married,p.employed,p.age_group,p.income_group,p.health,
      p.private_count,p.private_premium,'Window' as stage length=12
    from out.matched_people as m inner join work.final_baselines as f
      on m.aid_type=f.aid_type and m.match_set=f.match_set
    inner join out.panel as p on m.person_id=p.person_id and p.survey_year=m.event_year-1;
  quit;
  proc append base=work.balance_input data=work.after; run;
  proc append base=work.balance_input data=work.final_balance; run;
%mend;
%collect_balance;
data work.balance_long;
  set work.balance_input;
  length covariate $40;
  array categorical[7] sex region married employed age_group income_group health;
  array lower[7] _temporary_ (1 1 0 0 1 1 1);
  array upper[7] _temporary_ (2 2 1 1 4 5 3);
  do j=1 to dim(categorical);
    do level=lower[j] to upper[j];
      covariate=cats(vname(categorical[j]),'=',level);
      value=(categorical[j]=level);
      output;
    end;
  end;
  covariate='private_count'; value=private_count; output;
  covariate='private_premium'; value=private_premium; output;
  covariate='ps'; value=ps; output;
  keep aid_type event_year stage window treated covariate value;
run;
proc means data=work.balance_long nway n mean var;
  class aid_type event_year stage window treated covariate;
  var value;
  output out=work.balance_stats(drop=_type_ _freq_) n=n mean=mean var=variance;
run;
proc sql;
  create table work.balance_pairs as
  select a.aid_type,a.event_year,a.stage,a.window,a.covariate,
    a.n as n_treated,b.n as n_control,a.mean as mean_treated,b.mean as mean_control,
    a.variance as var_treated,b.variance as var_control
  from work.balance_stats as a inner join work.balance_stats as b
  on a.aid_type=b.aid_type and a.event_year=b.event_year and a.stage=b.stage
    and a.window=b.window and a.covariate=b.covariate
  where a.treated=1 and b.treated=0;
  create table work.balance_denominators as
  select aid_type,event_year,covariate,sqrt((var_treated+var_control)/2) as before_sd
  from work.balance_pairs where stage='Before';
  create table work.balance_with_sd as
  select a.*,b.before_sd from work.balance_pairs as a left join work.balance_denominators as b
  on a.aid_type=b.aid_type and a.event_year=b.event_year and a.covariate=b.covariate;
quit;
data out.balance;
  set work.balance_with_sd;
  difference=mean_treated-mean_control;
  smd=.;
  if before_sd>0 then smd=difference/before_sd;
  else if before_sd=0 and difference=0 then smd=0;
  absolute_smd=abs(smd);
  review_flag=(missing(smd) or absolute_smd>0.1);
run;
proc means data=out.analysis_panel nway n mean std min max;
  class aid_type window treated relative_time;
  var outpatient inpatient_days household_cost_usd;
  output out=out.event_time_means(drop=_type_ _freq_)
    n=outpatient_n inpatient_n spending_n
    mean=outpatient_mean inpatient_mean spending_mean
    std=outpatient_sd inpatient_sd spending_sd;
run;
proc means data=out.analysis_panel nway n mean std;
  class aid_type window treated post;
  var outpatient inpatient_days household_cost_usd;
  output out=out.pre_post_means(drop=_type_ _freq_)
    n=outpatient_n inpatient_n spending_n
    mean=outpatient_mean inpatient_mean spending_mean
    std=outpatient_sd inpatient_sd spending_sd;
run;
%export(out.run_settings,run_settings);
%export(out.household_merge_audit,household_merge_audit);
%export(out.cohort_flow,cohort_flow);
%export(out.matching_status,matching_status);
%export(out.window_flow,window_flow);
%export(out.analysis_counts,analysis_counts);
%export(out.balance,balance);
%export(out.event_time_means,event_time_means);
%export(out.pre_post_means,pre_post_means);
%export(out.health_change_summary,health_change_summary);
%export(out.model_status,model_status);
%export(out.variable_summary,variable_summary);

%macro export_model_tables;
  %local members n i member;
  proc sql noprint;
    select memname into :members separated by ' ' from dictionary.tables
    where libname='OUT' and (upcase(memname) like '%_ESTIMATE'
      or upcase(memname) like '%_CONVERGENCE' or upcase(memname) like '%_PARAMETERS');
  quit;
  %let n=%sysfunc(countw(%superq(members)));
  %do i=1 %to &n.;
    %let member=%scan(%superq(members),&i.);
    %export(out.&member.,&member.);
  %end;
%mend;
%export_model_tables;
