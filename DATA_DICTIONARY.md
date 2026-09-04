# Inputs and derived variables

## Required datasets

The local input directory must contain these SAS datasets. They are opened read-only.

| Dataset | Use |
|---|---|
| `koweps_hp01_12_long.sas7bdat` | Longitudinal person and household-linked variables |
| `koweps_h05_2010_beta10.sas7bdat` | 2010 household coverage, expenditure, and premium |
| `koweps_h06_2011_beta8.sas7bdat` | 2011 household variables |
| `koweps_h07_2012_beta8.sas7bdat` | 2012 household variables |
| `koweps_h08_2013_beta6.sas7bdat` | 2013 household variables |
| `koweps_h09_2014_beta4.sas7bdat` | 2014 household variables |
| `koweps_h10_2015_beta3.sas7bdat` | 2015 household variables |
| `koweps_h11_2016_beta2.sas7bdat` | 2016 household variables |

The supplied wave-12 household dataset is outside the configured study period and is not an input to this analysis. The year-range settings must remain within 2010–2016 unless the file mapping and historical constants are also extended.

## Identification and timing

| Variable | Source or definition | Notes |
|---|---|---|
| `person_id` | `h_pid` | Unique together with survey year |
| `household_key` | `h_merkey`, corresponding wave `hXX_merkey` | Complete household key, including split-household information |
| `household_lineage` | `h_id` | Not a unique household observation key; used for conservative clustering |
| `reference_year` | `year` | Codebook reference-year definition |
| `survey_year` | `year+1` | Historical wave-year labeling |
| `coverage` | Household `hXX01_5aq3` | 0 NHI, 1 MA I, 2 MA II; veterans/unsupported codes are missing |
| `event_year` | First eligible adjacent NHI-to-MA transition | Survey-labeled time zero |
| `relative_time` | `survey_year-event_year` | 0 is the first post-labeled year |
| `post` | `relative_time>=0` | Binary post-period indicator |
| `treated` | 1 switcher, 0 matched NHI control | Defined within MA type |
| `did` | `treated*post` | Numeric DiD interaction |
| `match_set` | Unique numeric type/cohort/set identifier | Same assigned event year within each set |

Coverage is taken from the household file. Long-file coverage is checked against it and discrepancies are saved. `h01_11aq5` is retained for inspection; it is not substituted without a timing decision. The source memo notes that coverage fields change across waves, and wave 11 contains within-year distinctions.

## Covariates and outcomes

| Variable | Source | Definition and units |
|---|---|---|
| `sex` | `h_g3` | 1 male, 2 female |
| `region` | `h_reg7` | 1 capital region for original codes 1–2; 2 other regions for 3–7 |
| `age` | `h_g4` | `survey_year+age_offset-birth_year`; default offset 1 |
| `age_group` | Derived age | 1 under 20; 2 20–39; 3 40–64; 4 65+; valid derivation range 0–120 |
| `married` | `h_g10` | 1 for source code 1; 0 for codes 0 and 2–6 |
| `employed` | `h_eco4` | 1 for codes 1–6; 0 for codes 7–9 |
| `equiv_monthly_income` | `h_din`, `h01_1` | Annual disposable income / 12 / square root of household size; 10,000 KRW |
| `income_group` | Equivalized income and year constants | Five historical threshold categories; missing income remains missing |
| `health` | `h_med2` | 3 good (1–2), 2 moderate (3), 1 poor (4–5); 9 missing |
| `private_count` | `h_med10` | Number of private insurance policies; unknown 99 missing |
| `private_premium` | `hXX05_3aq2` | Monthly household premium in 10,000 KRW; unknown 999 missing |
| `chronic` | `h_g9_1` | 0 none; 1 under six months (1–2); 2 six months or longer (3); 9 missing |
| `institution` | `h_med7` | 0 none; 1 other (4–5); 2 clinic-level (2,3,6); 3 hospital-level (1,7), following the historical grouping |
| `outpatient` | `h_med3` | Annual outpatient visits; nonnegative integer |
| `admissions` | `h_med4` | Annual admission count; nonnegative integer |
| `inpatient_days` | `h_med5` | Annual inpatient days; nonnegative integer |
| `days_per_admission` | Days / admissions | Defined only when admissions > 0; diagnostic variable |
| `household_cost_krw` | `hXX07_3aq8` | Monthly household spending in 10,000 KRW multiplied by 10,000 and 12 |
| `household_cost_usd` | Annualized KRW / historical exchange rate | Nominal historical conversion; not inflation-adjusted |
| `health_change` | Current minus adjacent previous `health` | Missing at a person's first observation or across a gap |

Missing-value handling is field-specific. Do not apply a universal rule that values 9, 99, or 999 are missing. The supplied wave-12 codebook explicitly describes unknown values for spending and premium; observed earlier-wave value distributions were cross-checked. If using different data releases, verify those codes against the corresponding wave codebooks.

The annual income thresholds and exchange rates appear in `out.year_constants` and in `02_build_panel.sas`. These fixed thresholds define five income categories; they are not sample-estimated quintile cut points.
