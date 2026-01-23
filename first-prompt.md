Act as a Senior R Shiny Developer and Data Science Educator. Your task is to write the complete, executable code for a single-file R Shiny application (app.R) that simulates a mass casualty triage scenario for high school students.

**Technical Constraints:**
1. **Stack:** Use `shiny` for the framework and `tidyverse` (specifically `dplyr`, `purrr`, `tidyr`, `stringr`, `ggplot2`) for all data manipulation and plotting.
2. **Style:** Adhere strictly to tidyverse coding conventions (pipes `|>`, snake_case).
3. **UI:** Use `bslib` for a clean, modern interface.

**App Context & Logic:**
The app simulates a disaster scene. Patients present with **multiple symptoms**. Students must classify individual symptoms to minimize "Emergency Life-Flights" (an expensive penalty). They can run the simulation once (to see specific patients) or 100 times (to see statistical averages).

**Data Requirements:**
- **Symptom Reference:** Create a master tibble of 10 distinct symptoms (e.g., "Minor Abrasions", "Chest Pain", "Unconscious").
- **Stochastic Severity:** Assign each symptom a `mean_wait` and `sd_wait`.
    - Minor symptoms: High means (e.g., 180 mins), moderate SD.
    - Critical symptoms: Low means (e.g., 15 mins), small SD.
- **Patient Generation (Function):**
    - Create a function that generates 50 patients.
    - Assign each patient **1 to 3 distinct symptoms** randomly.
    - **Wait Time Simulation:**
        - Identify the patient's "Critical Symptom" (lowest `mean_wait`).
        - Simulate `max_wait_time` using `rnorm` based on that symptom's stats (truncate at 1 min).
- **Simulation Loop:**
    - The app must support running $N$ simulations (User selects 1 or 100).
    - If $N=100$, iterate the generation/transport logic 100 times.
    - **Seed Logic:** Use `set.seed(input$seed + i)` inside the loop so the "first" run is always the same, but subsequent runs in the batch vary deterministically.

**Simulation Logic (The "Engine"):**
1. **Student Input:** Student assigns Triage Color (Green, Yellow, Red) to symptoms.
2. **Patient Classification:** Patient Color = Highest priority color of their symptoms (Red > Yellow > Green).
3. **Queueing:** Ambulances (5 units, 30 min trip) prioritize Red > Yellow > Green.
4. **Outcome:**
    - Calculate "Time Waited" based on queue position.
    - If `Time Waited > Simulated Max Wait`, Result = "Life-Flight". Else "Standard".

**User Interface Structure (2 Tabs):**

**Tab 1: Triage Station (Setup)**
- **Controls:**
    - Numeric Input: "Simulation Seed".
    - Radio Buttons: "Number of Simulations" (Options: "1", "100").
- **Classification Interface:** List of 10 symptoms with inputs to assign color.
- **Action:** "Run Simulation" button.

**Tab 2: After Action Report (Results)**
- **Top Level Metrics:**
    - If N=1: Show total Life-Flights.
    - If N=100: Show Average Life-Flights and a Histogram of Life-Flights per run.
- **Symptom Analysis Plots (Crucial for learning):**
    1.  **"The Deadly Symptoms":** A bar chart showing the % of patients with specific symptoms who required a Life-Flight. (Helping students identify which symptoms they might have under-prioritized).
    2.  **"Wait Time vs. Reality":** A boxplot with `Student Assigned Color` on the X-axis and `Actual Max Wait Time` on the Y-axis. This reveals if they put critical patients (low max wait) in the Green category (long queue).
- **Patient Data Table (DT):**
    - If N=1: Show all 50 patients.
    - If N=100: Show all patients from all simulations.

**Execution:**
- Write the code in a single block.
- Use `reactive()` and `map_dfr()` (or similar) to handle the 1 vs 100 simulation logic efficiently.
- Add comments explaining the seed iteration logic.