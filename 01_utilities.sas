%macro fail(message);
  %put ERROR: &message.;
  %abort cancel;
%mend;

%macro guard(stage);
  %if &syserr.>4 or &syscc.>4 %then %fail(&stage. failed. See the SAS log);
%mend;

%macro assert_empty(data,message);
  %local n;
  proc sql noprint; select count(*) into :n trimmed from &data.; quit;
  %if &n.>0 %then %fail(&message. See &data.);
%mend;

%macro unique(data,keys,report);
  proc sql;
    create table &report. as
    select &keys., count(*) as records
    from &data. group by &keys. having count(*)>1;
  quit;
  %assert_empty(&report.,Duplicate keys are not resolved by arbitrary deletion);
%mend;

%macro require(data,vars);
  %local ds i v rc;
  %if not %sysfunc(exist(&data.)) %then %fail(Missing input dataset &data.);
  %let ds=%sysfunc(open(&data.,i));
  %if &ds.=0 %then %fail(Cannot open &data.);
  %do i=1 %to %sysfunc(countw(&vars.));
    %let v=%scan(&vars.,&i.);
    %if %sysfunc(varnum(&ds.,&v.))=0 %then %do;
      %let rc=%sysfunc(close(&ds.));
      %fail(Missing variable &v. in &data.);
    %end;
    %if %sysfunc(vartype(&ds.,%sysfunc(varnum(&ds.,&v.)))) ne N %then %do;
      %let rc=%sysfunc(close(&ds.));
      %fail(Expected a numeric source variable &v. in &data.);
    %end;
  %end;
  %let rc=%sysfunc(close(&ds.));
%mend;

%macro export(data,name);
  %if %sysfunc(exist(&data.)) %then %do;
    proc export data=&data. outfile="&output_root./&name..csv"
      dbms=csv replace; run;
  %end;
%mend;

%macro initialize;
  %global output_root;
  %if &first_year.<2010 or &last_year.>2016 or &first_year.>=&last_year. %then
    %fail(The configured years must be an ordered subset of 2010 through 2016);
  %if &controls_per_case.<1 or %sysevalf(&controls_per_case. ne %sysfunc(int(&controls_per_case.))) %then
    %fail(controls_per_case must be a positive integer);
  %if %sysevalf(&ps_caliper.<=0 or &ps_caliper.>1) %then
    %fail(ps_caliper must be greater than zero and at most one);
  %if %length(%superq(raw_root))=0 %then %fail(Set raw_root in local_paths.sas);
  %if not %sysfunc(fileexist(%superq(raw_root))) %then %fail(Input directory does not exist);
  data _null_;
    length parent target made $2048;
    parent=cats(symget('code_root'),'/outputs');
    if not fileexist(parent) then made=dcreate('outputs',symget('code_root'));
    target=cats(parent,'/',symget('run_id'));
    if fileexist(target) then do;
      put 'ERROR: Run directory already exists. Choose a new run ID.';
      abort cancel;
    end;
    made=dcreate(symget('run_id'),parent);
    if missing(made) then do;
      put 'ERROR: Cannot create the output directory.';
      abort cancel;
    end;
    call symputx('output_root',target,'g');
  run;
  libname raw "&raw_root." access=readonly;
  libname out "&output_root.";
  %guard(Initialize libraries);
  data out.run_settings;
    length setting $40 value $2048;
    setting='first_year'; value="&first_year."; output;
    setting='last_year'; value="&last_year."; output;
    setting='controls_per_case'; value="&controls_per_case."; output;
    setting='ps_caliper'; value="&ps_caliper."; output;
    setting='match_seed'; value="&match_seed."; output;
    setting='age_offset'; value="&age_offset."; output;
    setting='sas_version'; value="&sysvlong4."; output;
    setting='design'; value='Baseline-matched balanced panel'; output;
  run;
  data out.model_status;
    length aid_type window 8 outcome $32 model $24 status $64;
    stop;
  run;
%mend;

/* Shared with the small synthetic checks. Negative income is valid. */
%macro derive_variables;
  coverage=.;
  if hh_coverage in (0,1,2) then coverage=hh_coverage;
  region=.;
  if h_reg7 in (1,2) then region=1;
  else if h_reg7 in (3,4,5,6,7) then region=2;
  sex=.; if h_g3 in (1,2) then sex=h_g3;
  age=.; age_group=.;
  if not missing(h_g4) then age=survey_year+&age_offset.-h_g4;
  if 0<=age and age<=120 then do;
    if age<20 then age_group=1;
    else if age<40 then age_group=2;
    else if age<65 then age_group=3;
    else age_group=4;
  end;
  married=.;
  if h_g10=1 then married=1;
  else if h_g10 in (0,2,3,4,5,6) then married=0;
  employed=.;
  if h_eco4 in (1,2,3,4,5,6) then employed=1;
  else if h_eco4 in (7,8,9) then employed=0;
  equiv_monthly_income=.; income_group=.;
  if not missing(h_din) and h01_1>0 then equiv_monthly_income=h_din/12/sqrt(h01_1);
  if nmiss(equiv_monthly_income,q1,q2,q3,q4)=0 then do;
    if equiv_monthly_income<=q1 then income_group=1;
    else if equiv_monthly_income<=q2 then income_group=2;
    else if equiv_monthly_income<=q3 then income_group=3;
    else if equiv_monthly_income<=q4 then income_group=4;
    else income_group=5;
  end;
  health=.;
  if h_med2 in (1,2) then health=3;
  else if h_med2=3 then health=2;
  else if h_med2 in (4,5) then health=1;
  private_count=.;
  if not missing(h_med10) and 0<=h_med10 and h_med10<99 then private_count=h_med10;
  private_premium=.;
  if not missing(monthly_private_premium) and 0<=monthly_private_premium
    and monthly_private_premium<999 then private_premium=monthly_private_premium;
  chronic=.;
  if h_g9_1=0 then chronic=0;
  else if h_g9_1 in (1,2) then chronic=1;
  else if h_g9_1=3 then chronic=2;
  institution=.;
  if h_med7=0 then institution=0;
  else if h_med7 in (4,5) then institution=1;
  else if h_med7 in (2,3,6) then institution=2;
  else if h_med7 in (1,7) then institution=3;
  outpatient=.; admissions=.; inpatient_days=.;
  if not missing(h_med3) and h_med3>=0 and h_med3=int(h_med3) then outpatient=h_med3;
  if not missing(h_med4) and h_med4>=0 and h_med4=int(h_med4) then admissions=h_med4;
  if not missing(h_med5) and h_med5>=0 and h_med5=int(h_med5) then inpatient_days=h_med5;
  days_per_admission=.;
  if admissions>0 and not missing(inpatient_days) then days_per_admission=inpatient_days/admissions;
  household_cost_krw=.; household_cost_usd=.;
  if not missing(monthly_medical_cost) and 0<=monthly_medical_cost
    and monthly_medical_cost<9999 then do;
    household_cost_krw=monthly_medical_cost*10000*12;
    if exchange_rate>0 then household_cost_usd=household_cost_krw/exchange_rate;
  end;
  baseline_complete=(nmiss(sex,region,married,employed,age_group,income_group,
    health,private_count,private_premium)=0);
%mend;

%macro adjacent_history;
  retain previous_year previous_coverage previous_health;
  if first.person_id then call missing(previous_year,previous_coverage,previous_health);
  adjacent=(not missing(previous_year) and survey_year=previous_year+1);
  transition_type=.;
  if adjacent and previous_coverage=0 and coverage in (1,2) then transition_type=coverage;
  health_change=.;
  if adjacent and nmiss(health,previous_health)=0 then health_change=health-previous_health;
  previous_year=survey_year;
  previous_coverage=coverage;
  previous_health=health;
%mend;
