# The Neural Mechanisms of Direct Linguistic Influence on Risk-Taking: A Visual Semantics Approach

An adaptive risky-choice paradigm testing whether **direct semantic priming** —
reading a risk-encouraging, risk-averse, or neutral linguistic prime — biases
risky choice, with concurrent EEG to examine the neural response to reward
feedback. Undergraduate research project (NYU Shanghai DURF), advised by
Prof. Xing Tian.

> **Scope note.** This project was designed with concurrent EEG, and the EEG
> paradigm below was fully implemented and used to collect an initial sample. The
> project was subsequently scoped to its **behavioral** component, so EEG data
> collection is currently on hold. The EEG code is kept here as a complete,
> working implementation of the intended design. See *Project status* below.

> **Data.** No participant data is included. All raw files contain subject
> identifiers and are excluded via `.gitignore`, consistent with IRB
> data-handling requirements. The paradigm regenerates its own stimuli each run.

---

## The question

Classic framing effects (Tversky & Kahneman, 1981) show that *describing* an
option differently can change preferences. This project asks a sharper question:
can **direct, explicit** linguistic persuasion — language that encourages risk,
caution, or neither, and that carries no information about the gamble itself —
**immediately bias risky choice**?

To make the effect measurable rather than swamped by obvious choices, each
participant's risk preference is first calibrated with an adaptive staircase, and
the formal task then presents gambles set at that person's own indifference
point — where any shift in risk preference is most visible. With
EEG, the question extends to the neural level: does the prime also change how the
brain responds to the *outcome* of a risky choice, indexed by the reward
positivity (RewP) to feedback?

---

## Task design

Each choice is between a **sure thing (ST)**, a smaller guaranteed amount, and a
**risky gamble (RG)**, a larger amount won with probability *p*. The gamble is
sized from a risk parameter `alpha` so that a person with that `alpha` would be
exactly indifferent:

```
RG = ST * (1/p)^(1/alpha)
```

A larger `alpha` means more risk-seeking. The study ran in two stages, each a
separate MATLAB / Psychtoolbox script.

### Stage 1: baseline calibration (`experiment/RiskDM_Alphatest.m`)

No primes. **5 blocks × 32 trials = 160 trials.** A single `alpha` is adjusted
after every choice by a step that shrinks with each reversal
(`0.1 → 0.05 → 0.02 → 0.01 → 0.005`, reversal count reset at the start of each
block), clamped to `[0.2, 2.0]`:

- chose the **sure thing** → `alpha` decreases;
- chose the **gamble** → `alpha` increases.

The participant's **baseline alpha** is the trimmed mean of the five block-final
estimates (the highest and lowest are dropped). The experimenter enters it into
Stage 2.

### Stage 2: formal primed task (`experiment/RiskDM_imageFormal.m`)

- **9 blocks × 24 trials = 216 trials per participant.** Each block uses a
  **single prime condition**; each condition appears in 3 blocks. The first block's
  condition is set by participant ID (ID mod 3) and each cycle of three is shuffled
  with no condition repeated across a cycle boundary.
- **Fixed offers.** Gambles are built from the participant's baseline alpha and do
  **not** adapt during the task, so every offer sits near that person's own
  indifference point. The logged `Trial_Indif_Alpha` = `ln(1/p) / ln(RG/ST)` is the
  indifference point implied by the presented (rounded) amounts.
- **Win probabilities:** 8 levels, `0.18–0.81` in steps of `0.09`, 3 trials each
  per block. Sure-thing amounts range from 11 to 24; gamble amounts are capped at 100.
  ST/RG screen sides are balanced within each block.
- **Trial sequence:** sentence-image prime (2.0 s, shown at 1/3 size) → fixation
  (0.8–1.2 s) → choice (≤ 5 s) → feedback (1.0 s) → fixation (0.8–1.2 s).
  Blocks are separated by a 30 s enforced rest.
- **Data safety:** every trial is appended to a UTF-8 text backup; if the run
  stops early, completed trials are saved to a `CrashSaved_*.xlsx` file.
- **Sample:** 31 participants were tested; 1 was excluded for guessing the purpose
  of the experiment, leaving **30 participants and 6,480 trials** (2,160 per
  condition; 7 timeouts, 0.11%).

> **Running Stage 2:** the script reads the primes from a hard-coded lab path
> (`base_img_path = 'F:\Desktop\risk\'`). Point it at `experiment/stimuli/` to run
> it from this repo.

**Choice coding:** `1 = RG (risky)`, `0 = ST (safe)`, `2 = Timeout` (no response
within 5 s).

### Stimuli (`experiment/stimuli/`)

24 sentence images per condition, each a short Chinese phrase:
`adventure` (risk-encouraging, e.g. *不入虎穴焉得虎子*), `conservative`
(risk-averse, e.g. *见好就收落袋为安*), and `neutral` (everyday statements, e.g.
*窗外树叶轻微晃动*). File names start with the condition letter and item number;
a few names carry encoding artifacts from the lab machine and are kept as-is
because the data logs refer to them by those exact names.

---

## Repository layout

```
experiment/
  RiskDM_Alphatest.m     Stage 1: baseline alpha calibration (staircase, no primes)
  RiskDM_imageFormal.m   Stage 2: formal primed task (the analyzed dataset)
  stimuli/               Prime images: adventure/, conservative/, neutral/
  RiskDM_withpicture.m   Earlier pilot (40 trials, adaptive per-probability alpha)
  RiskDM_EEG.py          PsychoPy EEG version, ported from the pilot
analysis/
  visualize_riskdm.py    Python — merge per-subject data, QC, paired tests, figures
  riskdm_glmm.R          R — trial-level logistic mixed models
  requirements.txt       Python dependencies for the analysis
```

---

## The pilot version (`RiskDM_withpicture.m`)

An earlier single-run version: 40 trials, 5 win probabilities
`[0.51, 0.63, 0.75, 0.83, 0.91]`, primes randomized trial by trial, and a separate
adaptive `alpha` for each probability. It was used during development and is not
the source of the analyzed data.

## The EEG version (`RiskDM_EEG.py`)

A faithful PsychoPy port of the pilot MATLAB paradigm (identical staircase,
amounts, and sequencing) with the additions needed for ERP work. It was fully implemented and
used to collect an initial sample before the project was scoped to behavior.

**Photodiode triggers.** On the prime frame and on the feedback frame, a 200×200
white square is drawn in the bottom-left corner *on the same flip* as the
stimulus, held for 50 ms, then removed. A photodiode over that square gives the
EEG system a hardware-precise onset marker — more reliable than software
timestamps for ERP work. (Square position matches the lab's `test_trigger_tone.m`
convention.)

**Logged onset times.** `Prime_Onset_Time` and `Feedback_Onset_Time` record the
exact flip time of each trigger frame, with event codes (`Prime_Code` 11/12/13;
`Feedback_Code` 21 = ST, 22 = RG win, 23 = RG loss).

### Which ERP, and locked to what

The target component is the **reward positivity (RewP)** — a frontocentral
feedback-locked component that is larger for rewarding than non-rewarding outcomes
and indexes reward prediction error. It is measured **time-locked to feedback
onset** (typically ~250–350 ms post-onset). The feedback-frame photodiode marks
that time-zero precisely, and `Feedback_Code` distinguishes the outcome types
(ST feedback / RG win / RG loss) needed to contrast rewarding vs. non-rewarding
feedback. The prime-onset trigger is logged as well but is not the primary
analysis lock.

### Trial timing — and a window distinction

```
Prime (2.0 s) → ISI (0.5 s) → Decision (≤5 s) → Jitter (0.8–1.2 s) → Feedback (1.0 s) → ITI (0.5 s)
```

The **jitter (0.8–1.2 s)** is a *random blank interval before feedback onset*. Its
only purpose is to decorrelate feedback timing from the choice, so the brain can't
anticipate exactly when feedback appears (which would contaminate the
feedback-locked response with anticipatory activity). It is not a
measurement/analysis window — the RewP is measured in a window *following*
feedback onset, not during the jitter that precedes it.

> **Sync tests.** The MATLAB version sets `SkipSyncTests = 1` for development
> convenience. Formal EEG collection should run with sync tests enabled on the
> lab's dedicated presentation machine, since ERP analysis depends on accurate
> frame timing.

---

## Analysis (`analysis/visualize_riskdm.py`)

Merges per-subject `RiskDM_FormalData_*.xlsx`, runs data-quality checks, and
produces condition comparisons. Highlights:

- **Provenance-safe subject IDs.** IDs are taken from the *filename*, not the
  in-file `SubID`, to avoid collisions when a subject number was reused; the
  script flags any raw-ID clashes rather than silently merging them.
- **QC report:** trials per subject, one-condition-per-block check, timeout rate.
- **Block-level summary:** per-block RG rate, final/initial PSE and their delta,
  mean RT, timeouts.
- **Paired tests** across the three conditions (RG rate and Final Alpha) with
  Cohen's *dz*.
- **Figures:** RG rate by condition (with within-subject paired lines), PSE
  violin plots, RT, within-block alpha trajectory, and an exploratory block-order
  check for fatigue/order effects.

### Run it

```bash
pip install -r analysis/requirements.txt
python analysis/visualize_riskdm.py --data-dir /path/to/your/xlsx
```

(No data ships with the repo, so this runs against your own local data folder.)

## Mixed models (`analysis/riskdm_glmm.R`)

Trial-level logistic mixed models of risky choice (`RG` = 1, `ST` = 0; timeouts
dropped), comparing a random-intercept model with one that adds **by-participant
random slopes for prime condition**. The random-slopes model fits much better
(likelihood-ratio χ²(5) = 178, p < .001) and is the one reported below. It also
reports versions with `neutral` as the reference level and with win probability
as a covariate.

```bash
Rscript analysis/riskdm_glmm.R /path/to/merged_trial_data.csv
```

The input is one merged CSV with one row per formal-task trial and columns
`SubID`, `Condition`, `Choice_Num`, and `Probability`. Requires the `lme4` package.

---

## Results (behavioral, N = 30)

**Risky choice shifted with the prime.** Participants chose the risky gamble most
often after adventure primes and least often after conservative primes:

| Condition | Risky-choice rate | Mean RT |
|---|---:|---:|
| adventure | 0.537 | 1.21 s |
| neutral | 0.463 | 1.22 s |
| conservative | 0.414 | 1.22 s |

| Comparison | Paired test (participant level) | Mixed model with random slopes |
|---|---|---|
| adventure vs. conservative | +12.3 pp, 95% CI [3.4, 21.2], t(29) = 2.83, p = .008, dz = 0.52 | OR = 1.88, 95% CI [1.19, 2.97], p = .007 |
| adventure vs. neutral | +7.4 pp, 95% CI [1.8, 13.0], t(29) = 2.71, p = .011, dz = 0.50 | OR = 1.46, 95% CI [1.11, 1.93], p = .007 |
| neutral vs. conservative | +4.9 pp, p = .055 | OR = 1.29, 95% CI [1.01, 1.64], p = .043 |

**Reaction time did not differ by condition** (F(2, 58) = 0.30, p = .741).

Because offers in the formal task are fixed by each participant's baseline alpha,
the risky-choice rate is the outcome measure. `Trial_Indif_Alpha` describes the
offer that was shown, not the participant's response, so it is not used as a
measure of the prime's effect.

---

## Requirements

- **MATLAB** with Psychtoolbox-3 (behavioral version)
- **Python 3.9+** with **PsychoPy** (EEG version)
- **Python 3.9+** with pandas, matplotlib, seaborn, openpyxl, scipy (analysis)
- **R** with `lme4` (mixed models)

---

## Project status

A two-track DURF (visual vs. auditory linguistic priming), run as parallel,
independent studies with no shared data; this repository covers the **visual
semantics** track. Behavioral data collection is complete (30 participants after
exclusion), and the results above come from that sample. The EEG paradigm is fully
implemented and an initial sample was collected, but the project was subsequently
scoped to its behavioral component, so EEG collection is currently on hold. The
design connects psycholinguistics (semantic priming) with neuroeconomics (risky
choice and reward processing) — asking whether language shifts not only risky
choice but the neural response to its outcomes.
