# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo contains two related deliverables for a College of Idaho outreach activity:

1. **`app.R`** — a single-file R Shiny app that simulates a mass casualty triage scenario. Students assign
   triage colors (Red/Yellow/Green/**Black**) to 10 realistic clinical symptoms, then run a simulation to
   see how many patients **died** because they waited too long for an ambulance (or were tagged Black and
   never transported at all). It teaches prioritization, queueing, and statistical thinking.
2. **`index.qmd`** — a short (~8-slide) Quarto `revealjs` deck used to introduce the presenter and walk
   through the activity before students use the app. It's intentionally brief — the whole activity, deck
   included, targets a 30-minute session. It's the sole page of a minimal Quarto **website** project (see
   `_quarto.yml`) so it can be deployed with `quarto publish gh-pages`.

`first-prompt.md` is the original spec used to generate the *first version* of `app.R`; treat it as
historical context, not a live source of truth — the app has since diverged substantially (obfuscated
symptom names replaced with realistic ones, Life-Flight outcome replaced with death, Black/Expectant added,
`N_AMBULANCES` is 10 not 5, etc.).

## Running the app

```r
# From R console, with working directory set to the repo root:
shiny::runApp("app.R")
```

Or open `app.R` in RStudio/Positron and click "Run App". Dependencies are managed with **renv**
(`renv.lock` pins R 4.5.2 and package versions) — run `renv::restore()` to install them.

## Rendering the slides

```bash
quarto render
```

This renders the whole Quarto website project (`_quarto.yml`, single page `index.qmd`) to `_site/`.

## Deployment

The app is deployed to **shinyapps.io** (not GitHub Pages/Shinylive — an earlier GitHub Actions +
Shinylive workflow was tried and reverted in commit `fc6b48a`, "Reverting to shinyapp.io"). Deployment
metadata lives in `rsconnect/shinyapps.io/efriedlander/high-school-triage-activity.dcf` and
`.posit/publish/`. Deploy via the Posit/RStudio "Publish" button or `rsconnect::deployApp()`.

`scripts/patch_shinylive.R` is leftover from the abandoned Shinylive approach and is not part of the
current deployment path.

The slide deck is a Quarto website project (`_quarto.yml`, `index.qmd`) published to **GitHub Pages** via
`quarto publish gh-pages`, which renders the project and pushes the `_site/` output to the `gh-pages`
branch. `_site/` and `.quarto/` are gitignored — nothing rendered is committed to `main`. This replaced the
earlier approach of committing a self-contained rendered HTML file (`triage_activity_slides.html` +
`triage_activity_slides_files/`) straight into `main` (see the `Deploy slide show` commit) and the
Posit-Connect-Cloud-based deploy recorded in `.posit/publish/`, both now superseded.

## Architecture of `app.R`

Everything lives in one file, organized into six numbered sections (search for `# --- N.` comments):

1. **Libraries** — shiny, bslib, tidyverse packages, DT, glue, ggforce (for `geom_sina`).
2. **Data and constants** — `SYMPTOMS_REFERENCE` is the master tibble of 10 realistic START-style clinical
   signs (e.g. "Absent Or Agonal Breathing", "No Palpable Radial Pulse"), each with a `mean_wait`/`sd_wait`
   (minutes after the incident before the condition becomes fatal without evacuation) and a `default_color`
   (always "Green" — students must actively upgrade priority). Severity is deliberately *not* obvious from
   the name alone, so students have to reason from simulated data rather than intuition. Key constants:
   - `TRIAGE_LEVELS <- c("Black", "Red", "Yellow", "Green")` — severity ranking used for classification;
     Black is ranked most severe so it outranks Red/Yellow/Green in the `min()` aggregation.
   - `TRIAGE_CHOICES <- c("Red", "Yellow", "Green", "Black")` — same four colors, in the order shown in the UI.
   - `TRANSPORT_PRIORITY <- c("Red", "Yellow", "Green")` — priority order for the ambulance queue; Black is
     excluded because Expectant patients are never transported.
   - `SCENE_ARRIVAL_DELAY <- 8` — a floor (minutes) under every patient's wait time, representing minimum
     time to reach/assess/load a patient. This is what makes the most severe symptom ("Absent Or Agonal
     Breathing", mean_wait 5) genuinely unsalvageable regardless of triage color — the pedagogical basis for
     when Black is the "correct" call. If you touch the symptom table or ambulance constants, re-verify this
     floor still holds (see calibration note below).
   - `N_PATIENTS`, `N_AMBULANCES`, `AMBULANCE_TRIP_TIME`, `AMBULANCE_ARRIVAL_RATE` — queue capacity knobs.
3. **`generate_patients()`** — builds a cohort of patients, each assigned 1–3 distinct symptoms. A
   patient's `max_wait_time` is drawn from `rnorm()` using the stats of their single most critical symptom
   (lowest `mean_wait`), truncated at 1 minute.
4. **UI** (`page_navbar` with two tabs):
   - **"Triage Station"**: sidebar with seed + number-of-simulations controls, and a card whose
     symptom `selectInput`s are generated dynamically via `purrr::pmap` + `!!!` splicing over
     `SYMPTOMS_REFERENCE` (input IDs are the snake_cased symptom names), choices = `TRIAGE_CHOICES`.
   - **"After Action Report"**: summary metrics UI, two plots (deadly-symptoms bar chart, triage-vs-wait
     sina plot), and a `DT` patient log table.
5. **Server logic**:
   - `observeEvent(input$run_simulation, ...)` is the core engine. It shows a modal with an animated
     ambulance parade, then for `n_sims` iterations (1 or 100): calls `set.seed(input$seed + i - 1)` so run
     1 is always reproducible for a given seed while later runs in a 100-run batch vary deterministically,
     generates patients, classifies each patient's color as the *most severe* color among their symptoms
     (via `factor(..., levels = TRIAGE_LEVELS, ordered = TRUE) |> min()`). Patients tagged Black are split
     off as `expectant_patients` *before* the queue runs (`time_waited = NA`, `result = "Died"`) — they
     never consume an ambulance slot. Everyone else is queued by `TRANSPORT_PRIORITY`
     (`N_AMBULANCES` initially free at `SCENE_ARRIVAL_DELAY`, new ones arrive per a Poisson process via
     `rexp`), and `result` is `"Died"` if `time_waited > max_wait_time`, else `"Survived"`. Both groups are
     `bind_rows()`-ed back together (as character, not factor, to avoid level mismatches) before the rest of
     the pipeline runs.
   - All plots (deadly-symptoms bar chart, death histogram for N=100) are pre-built **inside** the
     `observeEvent` and stashed in a `reactiveVal` (`simulation_results`), not built lazily in
     `renderPlot()`. This is intentional — it lets the modal cover the expensive work and the tab switch
     (`updateNavbarPage`) feels instant once the modal closes. Keep new expensive computation inside this
     observer rather than in output renderers.
   - The "Triage vs. Transport Time" plot (`wait_time_plot`) is filtered reactively by
     `input$outcome_filter` (Both/Died/Survived) and `input$symptom_filter` (All Symptoms or one
     specific symptom, via `purrr::map_lgl(symptoms, ~ x %in% .x)` against the `symptoms` list-column)
     at render time (cheap), unlike the pre-computed plots above. Black patients have `time_waited = NA`
     and are dropped from this plot (there's nothing to plot — they were never transported); the
     death/survival split it shows only covers transported patients.
6. **`shinyApp(ui, server)`** entry point.

**Calibration note:** the symptom `mean_wait`/`sd_wait` values and `SCENE_ARRIVAL_DELAY`/ambulance constants
were tuned (via an offline base-R re-simulation, not part of the app) so that: (a) a well-reasoned policy
roughly halves total deaths vs. doing nothing, (b) tagging the most severe symptom Black rather than Red
saves several expected lives by freeing ambulance capacity — Black has a real payoff, not just a label, and
(c) over-triaging too many symptoms into Red backfires by congesting the queue. If you change the symptom
table or queue constants, sanity-check that these three properties still hold.

## Conventions

- Tidyverse style throughout: native pipe `|>`, `snake_case` for variables/functions, heavy use of
  `dplyr`/`purrr`/`tidyr`.
- Symptom-related data flows through the app as a list-column (`symptoms`) that gets `unnest()`ed and
  `rename()`d to `symptom` whenever it needs to be joined against `SYMPTOMS_REFERENCE` or
  `student_triage_map` — this join key rename shows up in several places (`generate_patients`, the
  per-simulation classification step, and the deadly-symptoms aggregation).
