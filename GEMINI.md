# GEMINI.md

## Project Overview

This project is an R Shiny application designed for a high school data science activity. The application simulates a mass casualty triage scenario, teaching students about prioritization, resource allocation, and statistical thinking.

The core of the project is a single-file Shiny app (`app.R`) that allows students to:
1.  **Classify Symptoms:** Assign triage levels (Red, Yellow, Green) to various medical symptoms.
2.  **Run Simulations:** Execute a simulation with a set of patients, each having random symptoms. The simulation can be a single run or a statistical run of 100 simulations.
3.  **Analyze Results:** View an "After Action Report" that includes key metrics (like the number of "Life-Flights"), visualizations to identify critical symptoms, and a detailed log of all simulated patients.

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
