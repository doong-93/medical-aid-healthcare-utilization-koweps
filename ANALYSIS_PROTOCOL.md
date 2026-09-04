# Analysis protocol

## Scientific scope

The question is whether changes in annual health care utilization and household medical spending differ between people transitioning from NHI to MA and people observed to remain in NHI. MA type I and MA type II are analyzed separately. The analysis is explanatory and longitudinal; it is not a prediction model.

| Component | Implemented definition |
|---|---|
| Population | KoWePS person-year observations labeled survey years 2010–2016 |
| Unit | Person-year; household spending is attached to each observed member |
| Exposure | Adjacent observed NHI-to-MA I or NHI-to-MA II transition |
| Comparator | People with NHI at every observed wave in the selected period |
| Time zero | Survey-labeled transition year `g`; exact coverage start dates are not reconstructed |
| Baseline | Survey-labeled year `g-1`, using pre-transition covariates |
| Follow-up | Separate windows `[-1,0]`, `[-2,1]`, and `[-3,2]` relative to `g` |
| Primary outcomes | Annual outpatient visits, annual inpatient days, and annualized household medical spending |
| Primary contrast | Additive difference in mean annual outcomes between pre and post periods, comparing matched groups |
| Secondary contrast | Ratio of pre/post mean ratios for the two count outcomes |
| Target population | Matched, observed stable switchers with complete selected windows, rather than all MA entrants or the national population |

The source variable `year` denotes a reference year; the historical program labels the survey year as `year+1`. Both are retained. Utilization and expenditure refer to an annual reference period, while coverage timing is wave-based. The first post-labeled outcome can contain time before a midyear coverage change. This limits causal interpretation and should be resolved with exact coverage dates if a new causal analysis is intended. The 2016 coverage choice uses the source first-half-year field; later-half-year information is not silently substituted.

## Cohort construction

Coverage history is assessed before complete-case restrictions. An event requires observed consecutive years `g-1` and `g`, with NHI followed by MA. A transition across a gap is not treated as an adjacent transition.

The main cohort requires exactly one observed adjacent transition, NHI throughout observed pre-event history, and the same MA type throughout observed post-event history. People with unknown coverage, a reversal, another MA type, or multiple observed household lineages are excluded. Controls must have known NHI coverage throughout their observed history. Unobserved years are not imputed. The household-lineage condition allows the same person to remain within one cluster; it does not exclude every change in a complete household merge key.

These requirements select stable coverage trajectories using future observations. They can introduce selection bias and define a narrower population than all incident MA entrants. They are not equivalent to an intention-to-treat design. The cohort flow reports the restriction rather than hiding it in deduplication.

Each analysis window requires every member of a complete 1:3 matched set to have all `2W` annual observations and all three outcomes. The population can therefore differ across windows, and an entire matched set is removed if a member lacks a required year. Complete-window selection may be informative. No replacement match is made after this restriction.

## Matching

The propensity model includes sex, capital-region residence, marital status, employment, age category, historical income category, self-rated health, number of private insurance policies, monthly household private insurance premium, and event-year indicators. Categorical covariates enter as class effects. All covariates are measured at `g-1`; post-transition health and income do not determine the match.

Propensity models are pooled across event cohorts within MA type because some type II cohorts contain very few switchers. An NHI control can contribute a baseline record to more than one candidate event cohort during score estimation. Actual matching proceeds by event year in chronological order, uses only controls in that same event year, and uses each person once within an MA-type analysis. The same NHI person may be selected in the separate type I and type II analyses.

Matching uses greedy nearest neighbors, three controls per case, a fixed random seed, and an absolute probability caliper of 0.1. The caliper is not standardized by the PS or logit standard deviation. Partial sets are discarded. Greedy matching depends on order; the seed is recorded. Controls from incomplete discarded sets can be considered in later cohorts. These settings use native [PROC PSMATCH](https://support.sas.com/documentation/onlinedoc/stat/142/psmatch.pdf).

Assess overlap, separation, convergence, and balance. The balance report shows every category level and continuous covariate before matching, after matching, and after window restrictions, separately by event cohort. Standardized differences use the pooled before-match sample standard deviation as a fixed denominator. A missing standardized difference or absolute value above 0.1 is flagged for review, not automatically repaired. Type II has few eligible switchers, so a high-dimensional propensity model may remain unstable even after pooling. The program does not silently remove covariates, relax the caliper, or use a penalized fit.

## Outcome models and inference

Primary models use Gaussian identity-link GEE with a working independence correlation, event-cohort intercepts, treatment, post-period, and a numeric treatment-by-post interaction. The interaction coefficient estimates an additive mean contrast. A Gaussian working variance does not assert that spending is normally distributed; robust inference still requires adequate independent clusters and a suitable mean model. Negative fitted values can occur and should be examined.

Negative-binomial log-link GEE is provided as a sensitivity analysis for outpatient visits and inpatient days. Its interaction coefficient is a log ratio of ratios; exponentiating it gives the relative contrast, not an absolute change. The model uses a negative-binomial distribution without a zero-inflation component. Review zeros, dispersion, convergence, and predicted values.

GEE clusters use the observed household lineage, accounting for repeated people and related household observations within that lineage. This does not fully incorporate uncertainty from estimated propensity scores, matched-set construction, or dependencies across distinct lineages. Small-cluster inference can be unreliable; fewer than 30 clusters is flagged as a diagnostic, not a universal validity threshold. For publication-level inference, assess whether a design-specific resampling or alternative clustered estimator is needed. The source survey weights and complex sampling design are not incorporated; estimates are not nationally representative population effects.

The adjusted covariates are used in baseline matching. Chronic disease and medical institution type are retained for inspection, but contemporaneous values are not added to the outcome models because they could be affected by coverage. The pooled pre/post model assumes a common treatment contrast across included event cohorts and durations. It does not model arbitrary calendar-year shocks or heterogeneous dynamic effects.

SAS documents that [GEE is not available for zero-inflated models](https://support.sas.com/kb/30/333.html). The spending model uses a Gaussian identity link; the count sensitivity models use a negative-binomial log link. The [REPEATED statement](https://support.sas.com/documentation/cdl/en/statug/63962/HTML/default/statug_genmod_sect029.htm) supplies empirical standard errors by default.

## Identification and interpretation

A causal reading would require parallel untreated trends, adequate overlap, no anticipation, no relevant spillovers, comparable measurement, appropriate timing, and no unmeasured time-varying confounding or informative selection. Eligibility changes, deteriorating health, employment loss, disability, and household-income shocks are plausible threats. Matching observed baseline covariates does not resolve these threats.

For two- and three-year windows, the program fits an additive pre-period difference-in-slopes diagnostic and exports event-time means. A nonsignificant test does not establish parallel trends, especially in the small type II sample. The published article reported a pretrend problem for spending. New household-spending contrasts must not automatically be described as causal effects or as individual out-of-pocket costs.

