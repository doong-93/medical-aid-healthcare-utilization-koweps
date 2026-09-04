/* g is the survey-labeled transition year. Relative time 0 is first post.
   A W-year window is [-W, W-1], containing exactly W pre and W post years.
   Keep complete 1:3 sets with all years and all three outcomes observed. */
proc sql;
  create table work.matched_long as
  select m.aid_type,m.event_year,m.treated,m.match_set,m.ps,p.*
  from out.matched_people as m inner join out.panel as p
  on m.person_id=p.person_id;
quit;
data work.requested_windows;
  set work.matched_long;
  relative_time=survey_year-event_year;
  post=(relative_time>=0);
  did=treated*post;
  complete_outcomes=(nmiss(outpatient,inpatient_days,household_cost_usd)=0);
  do window=1 to 3;
    if -window<=relative_time and relative_time<=window-1 then output;
  end;
run;
proc sql;
  create table out.window_person_eligibility as
  select aid_type,match_set,person_id,window,count(*) as observed_rows,
    count(distinct survey_year) as observed_years,
    sum(complete_outcomes) as complete_years,
    min(relative_time) as first_relative_year,max(relative_time) as last_relative_year
  from work.requested_windows group by aid_type,match_set,person_id,window;
  create table work.complete_people as
  select * from out.window_person_eligibility
  where observed_years=2*window and complete_years=2*window
    and first_relative_year=-window and last_relative_year=window-1;
  create table work.complete_window_sets as
  select aid_type,match_set,window,count(*) as members
  from work.complete_people group by aid_type,match_set,window
  having count(*)=&controls_per_case.+1;
  create table out.analysis_panel as
  select p.* from work.requested_windows as p inner join work.complete_window_sets as s
  on p.aid_type=s.aid_type and p.match_set=s.match_set and p.window=s.window;
  create table out.window_flow as
  select a.aid_type,a.window,count(distinct a.match_set) as matched_sets_considered,
    count(distinct b.match_set) as complete_sets_retained
  from out.window_person_eligibility as a left join work.complete_window_sets as b
  on a.aid_type=b.aid_type and a.match_set=b.match_set and a.window=b.window
  group by a.aid_type,a.window;
  create table out.analysis_counts as
  select aid_type,window,treated,count(*) as person_years,
    count(distinct person_id) as people,count(distinct match_set) as match_sets,
    count(distinct household_lineage) as household_lineages
  from out.analysis_panel group by aid_type,window,treated;
quit;
%unique(out.analysis_panel,%str(aid_type,window,person_id,survey_year),out.duplicate_analysis_year);
data out.bad_event_alignment;
  set out.analysis_panel;
  if (treated=1 and post=0 and coverage ne 0)
    or (treated=1 and post=1 and coverage ne aid_type)
    or (treated=0 and coverage ne 0);
run;
%assert_empty(out.bad_event_alignment,Coverage is inconsistent with assigned event time);

/* Health-change supplement: comparisons use adjacent years only. */
proc sql;
  create table work.matched_health as
  select m.aid_type,m.treated,h.survey_year-m.event_year as relative_time,h.health_change
  from out.matched_people as m inner join out.coverage_history as h
  on m.person_id=h.person_id;
quit;
proc means data=work.matched_health nway n mean std;
  class aid_type treated relative_time;
  var health_change;
  output out=out.health_change_summary(drop=_type_ _freq_) n=n mean=mean std=sd;
run;
