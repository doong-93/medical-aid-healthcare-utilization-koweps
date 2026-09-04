/* Identify transitions before excluding incomplete covariate records.
   One eligible first-ever observed NHI-to-MA transition per person. */
proc sql;
  create table out.person_history as
  select person_id, min(survey_year) as first_observed_year,
    max(survey_year) as last_observed_year, count(*) as observed_years,
    sum(missing(coverage)) as unknown_coverage_years,
    sum(coverage ne 0) as non_nhi_years,
    count(distinct household_lineage) as lineage_count,
    sum(not missing(transition_type)) as transition_count
  from out.coverage_history group by person_id;
  create table work.first_event as
  select person_id, min(survey_year) as event_year
  from out.coverage_history where transition_type in (1,2) group by person_id;
  create table work.event_candidates as
  select e.*, h.transition_type as aid_type
  from work.first_event as e inner join out.coverage_history as h
  on e.person_id=h.person_id and e.event_year=h.survey_year;
  create table out.case_eligibility as
  select e.person_id,e.event_year,e.aid_type,
    p.unknown_coverage_years,p.lineage_count,p.transition_count,
    sum(h.survey_year<e.event_year and h.coverage ne 0) as pre_non_nhi,
    sum(h.survey_year>=e.event_year and h.coverage ne e.aid_type) as post_other_coverage
  from work.event_candidates as e inner join out.person_history as p
  on e.person_id=p.person_id inner join out.coverage_history as h
  on e.person_id=h.person_id
  group by e.person_id,e.event_year,e.aid_type,p.unknown_coverage_years,
    p.lineage_count,p.transition_count;
  create table out.eligible_cases as
  select * from out.case_eligibility
  where unknown_coverage_years=0 and lineage_count=1 and transition_count=1
    and pre_non_nhi=0 and post_other_coverage=0;
  create table out.eligible_controls as
  select * from out.person_history
  where unknown_coverage_years=0 and non_nhi_years=0 and lineage_count=1;
  create table out.cohort_flow as
  select 'Observed people' as stage length=64, count(*) as people
    from out.person_history
  union all select 'People with an adjacent NHI-to-MA event', count(*) from out.case_eligibility
  union all select 'Stable eligible MA I cases', count(*) from out.eligible_cases where aid_type=1
  union all select 'Stable eligible MA II cases', count(*) from out.eligible_cases where aid_type=2
  union all select 'Observed NHI-only control pool', count(*) from out.eligible_controls;
quit;
/* Stable coverage throughout observed follow-up is a selection assumption.
   Missing years are not treated as observed coverage or consecutive exposure. */
%unique(out.eligible_cases,person_id,out.duplicate_cases);
