# Medical Aid transitions and health care utilization (Korea Welfare Panel Study)

This folder contains a SAS analysis workflow for the comparison of transitions from National Health Insurance (NHI) to Medical Aid (MA) type I or type II with continued NHI coverage in the Korea Welfare Panel Study (KoWePS).

**Publication status: Published.**

Lee DW, Jang J, Choi DW, Jang SI, Park EC. The effect of shifting medical coverage from National Health Insurance to Medical Aid type I and type II on health care utilization and out-of-pocket spending in South Korea. *BMC Health Services Research*. 2020;20:979. [Published article](https://doi.org/10.1186/s12913-020-05778-2).

## Files and execution order

| File | Purpose |
|---|---|
| `00_run_all.sas` | Run the full workflow in order |
| `00_config.sas` | Analysis years, matching settings, and model options |
| `local_paths.example.sas` | Template for the local input directory |
| `01_utilities.sas` | Input assertions, recoding, and adjacent-year checks |
| `02_build_panel.sas` | Read and validate person and household files |
| `03_define_cohorts.sas` | Identify eligible MA transitions and NHI controls |
| `04_match.sas` | Baseline propensity scores and 1:3 matching |
| `05_build_windows.sas` | Construct balanced 1-, 2-, and 3-year pre/post windows |
| `06_models.sas` | Additive DiD, count-model sensitivity analyses, and pretrend diagnostics |
| `07_reports.sas` | Balance tables, counts, time profiles, and model exports |
| `Run_Analysis.ps1` | Windows launcher with separate check, integration, and full modes |
| `tests/` | Synthetic recoding, temporal, known-contrast, and pipeline checks |

Use SAS 9.4 with SAS/STAT 14.2 or later, including PROC PSMATCH, PROC LOGISTIC, and PROC GENMOD. No downloaded matching macro is required. Run with UTF-8 encoding.

From PowerShell in this directory:

```powershell
.\Run_Analysis.ps1 -Mode Check
.\Run_Analysis.ps1 -Mode Integration
.\Run_Analysis.ps1 -Mode Full
```

Run the core and integration checks, then run the research analysis. The default launcher mode is `Check`; it does not access the research data. If SAS is installed elsewhere, provide `-SasExecutable` with the full executable path. In SAS's enhanced editor, `00_run_all.sas` can locate its directory through `SAS_EXECFILEPATH`; otherwise set the `MA_DID_CODE` environment variable.

Copy `local_paths.example.sas` to `local_paths.sas` and set `raw_root` to the folder containing the required SAS datasets. Alternatively, set the `MA_DID_RAW` environment variable. Keep the `%nrstr(...)` wrapper when the path contains semicolons or other macro-sensitive characters. The local configuration is excluded from version control.

## Outputs to review

Each run writes a new directory under `outputs/`; logs are stored under `logs/`. No existing run directory is reused. Review `cohort_flow.csv`, `matching_status.csv`, `window_flow.csv`, `analysis_counts.csv`, `balance.csv`, `event_time_means.csv`, and `model_status.csv` before interpreting estimates. A completion marker means the workflow reached its end; it does not mean that every model was estimable or scientifically adequate.

The primary `additive` estimate is a difference in annual visits, inpatient days, or annualized household spending. The `nb` estimate is on the log ratio-of-ratios scale. The `pre` tables assess differences in pre-period slopes. Outcome indices in filenames are 1 = outpatient visits, 2 = inpatient days, and 3 = household spending in converted USD.

Generated SAS datasets contain participant identifiers and must remain local. The deliverable contains code and aggregate documentation; `.gitignore` excludes source data, participant-level outputs, logs, and local paths.

Read [ANALYSIS_PROTOCOL.md](ANALYSIS_PROTOCOL.md) for the population, time origin, estimands, and assumptions, and [DATA_DICTIONARY.md](DATA_DICTIONARY.md) for variable definitions.
