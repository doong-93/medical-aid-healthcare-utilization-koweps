/* Select the documented reference years, then attach household observations
   using the full household merge key and survey year. */
%let long_vars=h_merkey h_pid year h_id h_reg7 h_din h01_1 h_hc h01_5aq3
  h01_11aq5 h_g3 h_g4 h_g10 h_eco4 h_med3 h_med4 h_med5 h_med7 h_g9_1 h_med10 h_med2;
%require(raw.koweps_hp01_12_long,&long_vars.);
data work.person_source;
  set raw.koweps_hp01_12_long(keep=&long_vars.);
  survey_year=year+1;
  if &first_year.<=survey_year and survey_year<=&last_year.;
  person_id=h_pid; household_key=h_merkey; household_lineage=h_id;
  reference_year=year;
run;
%unique(work.person_source,%str(person_id,survey_year),out.duplicate_person_year);
data out.missing_person_keys;
  set work.person_source;
  if nmiss(person_id,household_key,household_lineage,survey_year)>0;
run;
%assert_empty(out.missing_person_keys,Missing person or household keys);

%macro household(wave,year,member);
  %local prefix;
  %let prefix=h%sysfunc(putn(&wave.,z2.));
  %require(raw.&member.,&prefix._merkey &prefix._id &prefix.01_5aq3
    &prefix.07_3aq8 &prefix.05_3aq2);
  data work.hh&wave.;
    set raw.&member.(keep=&prefix._merkey &prefix._id &prefix.01_5aq3
      &prefix.07_3aq8 &prefix.05_3aq2);
    household_key=&prefix._merkey;
    household_lineage_source=&prefix._id;
    survey_year=&year.;
    hh_coverage=&prefix.01_5aq3;
    monthly_medical_cost=&prefix.07_3aq8;
    monthly_private_premium=&prefix.05_3aq2;
    keep household_key household_lineage_source survey_year hh_coverage
      monthly_medical_cost monthly_private_premium;
  run;
%mend;
%household(5,2010,koweps_h05_2010_beta10);
%household(6,2011,koweps_h06_2011_beta8);
%household(7,2012,koweps_h07_2012_beta8);
%household(8,2013,koweps_h08_2013_beta6);
%household(9,2014,koweps_h09_2014_beta4);
%household(10,2015,koweps_h10_2015_beta3);
%household(11,2016,koweps_h11_2016_beta2);
data work.households;
  set work.hh5-work.hh11;
  if &first_year.<=survey_year and survey_year<=&last_year.;
run;
%unique(work.households,%str(household_key,survey_year),out.duplicate_household_year);
data out.missing_household_keys;
  set work.households;
  if nmiss(household_key,household_lineage_source,survey_year)>0;
run;
%assert_empty(out.missing_household_keys,Missing household keys);

proc sql;
  create table work.joined as
  select a.*, b.household_lineage_source, b.hh_coverage,
    b.monthly_medical_cost, b.monthly_private_premium,
    (not missing(b.household_key)) as household_matched
  from work.person_source as a left join work.households as b
  on a.household_key=b.household_key and a.survey_year=b.survey_year;
  create table out.household_merge_audit as
  select count(*) as joined_rows, sum(household_matched=0) as unmatched_rows,
    sum(household_lineage ne household_lineage_source) as lineage_disagreements,
    sum(h01_5aq3 ne hh_coverage) as coverage_disagreements from work.joined;
quit;
%unique(work.joined,%str(person_id,survey_year),out.duplicate_joined_year);
data out.unmatched_households out.lineage_disagreements out.coverage_disagreements;
  set work.joined;
  if household_matched=0 then output out.unmatched_households;
  if household_lineage ne household_lineage_source then output out.lineage_disagreements;
  if h01_5aq3 ne hh_coverage then output out.coverage_disagreements;
run;
%assert_empty(out.unmatched_households,Unmatched household records);
%assert_empty(out.lineage_disagreements,Household lineage mismatch);

/* Fixed study income thresholds and currency conversion factors. */
data out.year_constants;
  input survey_year q1 q2 q3 q4 exchange_rate;
  datalines;
2010 93.0 137.7 178.8 238.9 1134.8
2011 97.3 145.5 188.6 253.4 1151.8
2012 105.7 154.5 201.6 267.2 1070.6
2013 109.3 159.2 207.2 273.9 1055.4
2014 113.2 164.4 213.1 282.9 1099.3
2015 118.9 170.0 217.7 284.4 1172.5
2016 117.8 170.0 220.5 292.3 1207.7
;
run;
proc sql;
  create table work.with_constants as
  select a.*, b.q1,b.q2,b.q3,b.q4,b.exchange_rate
  from work.joined as a left join out.year_constants as b
  on a.survey_year=b.survey_year;
quit;
data out.panel;
  set work.with_constants;
  %derive_variables;
  label survey_year='Survey wave year (reference year plus one)'
    reference_year='Source reference year'
    coverage='Household coverage: 0 NHI, 1 MA I, 2 MA II'
    income_group='Income category using historical source thresholds'
    private_premium='Monthly household private insurance premium (10,000 KRW)'
    outpatient='Annual outpatient visits'
    inpatient_days='Annual inpatient days'
    household_cost_krw='Annualized household medical spending (nominal KRW)'
    household_cost_usd='Annualized household medical spending (historical USD conversion)';
run;
proc sort data=out.panel; by person_id survey_year; run;
data out.coverage_history;
  set out.panel;
  by person_id survey_year;
  %adjacent_history;
run;
proc means data=out.panel n nmiss min p50 p95 p99 max;
  var age equiv_monthly_income outpatient admissions inpatient_days
    household_cost_usd private_count private_premium;
  ods output summary=out.variable_summary;
run;
proc freq data=out.panel;
  tables survey_year*coverage sex age_group income_group employed health chronic
    institution baseline_complete / missing;
run;
