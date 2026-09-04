/* Synthetic tests only. No research data or source files are read. */
%let code_root=%qsysfunc(sysget(MA_DID_CODE));
%let age_offset=1;
%include "&code_root./01_utilities.sas";
libname out "%sysget(MA_DID_TEST_OUT)";

data work.fixture;
  do test=1 to 6;
    survey_year=2013; hh_coverage=0; h_reg7=1; h_g3=1; h_g4=1970;
    h_g10=1; h_eco4=9; h_din=1200; h01_1=1;
    q1=100; q2=150; q3=200; q4=300;
    h_med2=2; h_med10=2; monthly_private_premium=10;
    h_g9_1=0; h_med7=2; h_med3=99; h_med4=0; h_med5=0;
    monthly_medical_cost=12.5; exchange_rate=1000;
    if test=1 then call missing(h_g4,h_din);
    if test=2 then do; h_din=-1200; h_g9_1=9; h_med10=99; monthly_private_premium=999; end;
    if test=3 then do; h_med2=9; monthly_medical_cost=9999; hh_coverage=3; end;
    if test=4 then do; h_med10=9; h01_1=9; end;
    if test=5 then do; monthly_medical_cost=999; end;
    if test=6 then do; h_med4=2; h_med5=5; end;
    %derive_variables;
    output;
  end;
run;
data out.failed_recode_tests;
  set work.fixture;
  length failure $160;
  if test=1 and (not missing(age_group) or not missing(income_group)) then
    failure='Missing birth year or income was assigned a valid category';
  if test=2 and (income_group ne 1 or not missing(chronic) or not missing(private_count)
      or not missing(private_premium) or employed ne 0) then failure='Sentinel or negative-income handling failed';
  if test=3 and (not missing(health) or not missing(household_cost_usd) or not missing(coverage)) then
    failure='Unknown health, spending, or unsupported coverage was retained';
  if test=4 and (private_count ne 9 or h01_1 ne 9 or outpatient ne 99) then
    failure='A legitimate value of 9 or 99 was treated as a universal sentinel';
  if test=5 and household_cost_krw ne 119880000 then failure='Valid spending value 999 was discarded';
  if test=6 and days_per_admission ne 2.5 then failure='Days per admission is incorrect';
  if test<6 and not missing(days_per_admission) then failure='Division by zero was not guarded';
  if not missing(failure);
run;
%assert_empty(out.failed_recode_tests,Recode tests failed);

data work.history_fixture;
  input person_id survey_year coverage health;
  datalines;
1 2010 0 3
1 2011 1 2
2 2010 0 3
2 2012 2 1
3 2010 1 2
3 2011 0 2
3 2012 2 1
;
run;
data work.checked_history;
  set work.history_fixture;
  by person_id survey_year;
  %adjacent_history;
run;
data out.failed_history_tests;
  set work.checked_history;
  length failure $160;
  if person_id=1 and survey_year=2011 and (transition_type ne 1 or health_change ne -1) then
    failure='An adjacent transition or health change was not detected';
  if person_id=2 and survey_year=2012 and (not missing(transition_type) or not missing(health_change)) then
    failure='A gap was incorrectly treated as adjacent follow-up';
  if not missing(failure);
run;
%assert_empty(out.failed_history_tests,Adjacent-history tests failed);

/* A hand-calculated additive DiD of 7 is independent of the study outcomes. */
data work.did_fixture;
  do household_lineage=1 to 80;
    treated=(household_lineage>40);
    do post=0 to 1;
      did=treated*post;
      outcome=10+2*treated+3*post+7*did+mod(household_lineage,5);
      output;
    end;
  end;
run;
ods output Estimates=out.synthetic_did_estimate;
proc genmod data=work.did_fixture;
  class household_lineage;
  model outcome=treated post did / dist=normal link=identity;
  repeated subject=household_lineage / type=ind;
  estimate 'Known additive DiD' did 1;
run;
ods output close;
%guard(Synthetic GEE);
data out.failed_did_test;
  set out.synthetic_did_estimate;
  if abs(LBetaEstimate-7)>1e-8 or missing(LBetaEstimate);
run;
%assert_empty(out.failed_did_test,Known DiD estimate was not recovered);
%put NOTE: CORE_TESTS_PASSED;
