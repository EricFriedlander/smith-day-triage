# GEMINI.md

## Project Overview

This project is an R Shiny application designed for a data science activity teaching prioritization, resource allocation, and statistical thinking through a mass casualty triage scenario. The whole activity (short slide intro + app) is designed to fit in about 30 minutes.

The core of the project is a single-file Shiny app (`app.R`) that allows students to:
1.  **Classify Symptoms:** Assign triage levels (Red, Yellow, Green, or **Black/Expectant**) to 10 realistic clinical symptoms (e.g. "Absent Or Agonal Breathing", "No Palpable Radial Pulse"). Symptom severity is not obvious from the name alone and symptoms are displayed in alphabetical order, so students must reason from simulated data rather than intuition. All symptoms default to "Green". **Black** means the patient is never sent an ambulance at all — it should be reserved for symptoms so severe that transport wouldn't save the patient anyway.
2.  **Run Simulations:** Execute a simulation with a set of patients, each having random symptoms. The simulation can be a single run or a statistical run of 100 simulations.
3.  **Analyze Results:** View an "After Action Report" that includes key metrics. For a single simulation, it shows the total number of **deaths**. For a statistical run of 100 simulations, it provides the average, median, minimum, and maximum number of deaths. A patient dies if they wait longer than their symptom allows before transport, or if they were tagged Black (and so never transported). The report also includes visualizations to identify the deadliest symptoms, and a detailed log of all simulated patients. A "Triage vs. Transport Time" plot lets students compare wait time against assigned triage color, filterable by outcome (Died, Survived, or Both); Black patients have no wait time and don't appear in this plot since they were never transported.

When the user clicks the "Run Simulation" button, the application displays a loading animation of moving ambulances while it runs the simulation and pre-generates all plots for the report. Once the processing is complete, the user is automatically taken to the "After Action Report" tab to view the results. This ensures a smooth and responsive user experience.

The primary technologies used are:
*   **R:** The programming language.
*   **Shiny:** The web application framework for R.
*   **bslib:** For modern, themed UI components.
*   **tidyverse:** A collection of R packages for data science, used heavily for data manipulation and visualization (`ggplot2`).
*   **DT:** To render interactive data tables.

## Building and Running the Application

### Prerequisites

You must have R installed on your system. You will also need to install the following R packages:

```R
install.packages(c("shiny", "bslib", "tidyverse", "DT"))
```

### Running the App

There are two primary ways to run the Shiny application:

1.  **Using RStudio:**
    *   Open the `app.R` file in RStudio.
    *   Click the "Run App" button that appears at the top of the editor pane.

2.  **From the R Console:**
    *   Open your R console.
    *   Set your working directory to the root of this project folder.
    *   Run the following command:
        ```R
        shiny::runApp('app.R')
        ```

## Development Conventions

The `app.R` code follows modern R and `tidyverse` style conventions.

*   **Tidyverse Syntax:** The code makes extensive use of `tidyverse` packages and syntax, including the native R pipe (`|>`).
*   **Variable Naming:** Variables and functions are named using `snake_case` (e.g., `run_simulation`, `patient_id`).
*   **File Structure:** The application is self-contained within the `app.R` file, which includes the UI, server logic, and simulation functions.

## Shinylive Deployment

The app can be deployed as a static website using [Shinylive](https://posit-dev.github.io/r-shinylive/). A GitHub Actions workflow (`.github/workflows/deploy-app.yaml`) handles automated deployment to GitHub Pages.

### Known Issues & Workarounds

Due to version mismatches between the project's `renv.lock` and the Shinylive WASM repository, a patching script (`scripts/patch_shinylive.R`) is used to:

1. Download compatible versions of `shiny`, `bslib`, `munsell`, and `colorspace`.
2. Update the package metadata to register these packages.

**Important:** Do NOT add `glue` to the patch script - it conflicts with the base Shinylive distribution.

### Manual Deployment

```bash
# Export the app
Rscript -e 'shinylive::export("myapp", "site")'

# Patch missing packages
Rscript scripts/patch_shinylive.R

# Serve locally
Rscript -e 'httpuv::runStaticServer("site")'
```
