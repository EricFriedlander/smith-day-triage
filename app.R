#
# Mass Casualty Triage Simulation - R Shiny App
# For High School Data Science Education
#
# Teaches concepts of prioritization, resource allocation, and statistical thinking.
#

# --- 1. Load Libraries ---
# Ensure these packages are installed: install.packages(c("shiny", "bslib", "tidyverse", "DT"))
library(shiny)
library(bslib)
library(dplyr)
library(ggplot2)
library(purrr)
library(stringr)
library(tidyr)
library(tibble)
library(forcats)
library(readr)
library(DT)
library(glue)

# --- 2. Data and Constants ---

# A master tibble of all possible symptoms.
# mean_wait: Average time (minutes) a patient can wait before needing critical care.
# sd_wait: Standard deviation, representing variability.

multiplier <- 1
SYMPTOMS_REFERENCE <- tibble::tribble(
  ~symptom, ~mean_wait, ~sd_wait, ~default_color,
  # Critical Symptoms (low wait times)
  "Unconscious", 15, 3, "Red",
  "Severe Bleeding", 20, 5, "Red",
  "Chest Pain", 25, 5, "Red",
  "Difficulty Breathing", 30, 8, "Red",
  # Moderate Symptoms
  "Abdominal Pain", 90, 20, "Yellow",
  "Concussion", 120, 30, "Yellow",
  "Deep Laceration", 150, 40, "Yellow",
  # Minor Symptoms (high wait times)
  "Simple Fracture", 240, 60, "Green",
  "Sprain", 300, 60, "Green",
  "Minor Abrasions", 360, 60, "Green"
) |>
  mutate(
    mean_wait = mean_wait * multiplier,
    sd_wait = sd_wait * multiplier
  )

# Simulation constants
N_PATIENTS <- 50
N_AMBULANCES <- 10
AMBULANCE_TRIP_TIME <- 15 # minutes for a round trip
AMBULANCE_ARRIVAL_RATE <- 0.1 # Average number of new ambulances arriving per minute
TRIAGE_LEVELS <- c("Red", "Yellow", "Green") # Highest to lowest priority

# --- 3. Patient Generation Function ---

#' Generate a cohort of patients with random symptoms and simulated wait times.
#'
#' @param n_patients The number of patients to generate.
#' @param symptoms_ref The reference tibble of symptoms.
#' @return A tibble of patients, where each row is a patient and `symptoms` is a list-column.
generate_patients <- function(n_patients, symptoms_ref) {
  # Create a base tibble of patient IDs
  # browser()
  patients <- tibble(patient_id = 1:n_patients) |>
    # For each patient, assign 1 to 3 distinct symptoms randomly
    mutate(
      symptoms = purrr::map(patient_id, ~ {
        symptoms_ref |>
          slice_sample(n = sample(1:3, 1)) |>
          pull(symptom)
      })
    )

  # For each patient, calculate their maximum tolerable wait time.
  # This is determined by their single most critical symptom.
  patients_with_wait_times <- patients |>
    # Create a row for each symptom a patient has
    tidyr::unnest(symptoms) |>
    # rename symptoms to symptom so join works
    rename(symptom = symptoms) |>
    # Join the symptom reference data to get wait time statistics
    left_join(symptoms_ref, by = "symptom") |>
    # For each patient, find their most critical symptom (lowest mean_wait)
    group_by(patient_id) |>
    summarise(
      critical_symptom = symptom[which.min(mean_wait)],
      mean_wait = min(mean_wait),
      sd_wait = sd_wait[which.min(mean_wait)],
      # Re-nest the full list of symptoms for this patient
      symptoms = list(unique(symptom))
    ) |>
    ungroup() |>
    # Simulate the actual max_wait_time using a normal distribution
    # based on the stats of their most critical symptom.
    rowwise() |>
    mutate(
      max_wait_time = round(rnorm(1, mean = mean_wait, sd = sd_wait))
    ) |>
    # Ensure wait time is at least 1 minute.
    mutate(max_wait_time = if_else(max_wait_time < 1, 1, max_wait_time)) |>
    select(patient_id, symptoms, max_wait_time)

  return(patients_with_wait_times)
}


# --- 4. UI Definition ---
ui <- page_navbar(
  id = "main_nav",
  title = "Mass Casualty Triage Simulator",
  theme = bs_theme(version = 5, bootswatch = "cyborg"),
  fillable = FALSE,
  header = tags$head(
    tags$style(HTML("
      @keyframes slide {
        0% { transform: translateX(-100px); }
        100% { transform: translateX(500px); }
      }
      .ambulance-parade {
        height: 50px;
        width: 100%;
        overflow: hidden;
        position: relative;
      }
      .ambulance-icon {
        font-size: 40px;
        position: absolute;
        animation: slide 3s linear infinite;
        animation-fill-mode: both;
      }
    "))
  ),

  # ## TAB 1: TRIAGE STATION (SETUP) ##
  nav_panel(
    title = "Triage Station",
    layout_sidebar(
      sidebar = sidebar(
        title = "Simulation Controls",
        numericInput("seed", "Simulation Seed", value = 123, min = 1),
        radioButtons(
          "n_simulations",
          "Number of Simulations",
          choices = c("Single Run" = 1, "Statistical Run (100)" = 100),
          selected = 1
        ),
        actionButton("run_simulation", "Run Simulation", class = "btn-primary w-100")
      ),
      card(
        card_header("Symptom Triage Classification"),
        p("Assign a triage color to each potential symptom. This will determine patient priority."),
        # Dynamically generate select inputs for each symptom
        !!!purrr::pmap(list(SYMPTOMS_REFERENCE$symptom, SYMPTOMS_REFERENCE$default_color), ~ {
          # Create a sanitized ID for the input control
          input_id <- str_to_lower(str_replace_all(..1, " ", "_"))
          selectInput(
            inputId = input_id,
            label = ..1,
            choices = TRIAGE_LEVELS,
            selected = ..2
          )
        })
      )
    )
  ),

  # ## TAB 2: AFTER ACTION REPORT (RESULTS) ##
  nav_panel(
    title = "After Action Report",
    # Top-level metrics (conditional on N=1 or N=100)
    uiOutput("results_summary_ui"),
    layout_columns(
      col_widths = c(6, 6),
      # Plot 1: Which symptoms led to life-flights?
      card(
        card_header("Analysis: The Deadly Symptoms"),
        p("This chart shows the percentage of patients with a given symptom who required a Life-Flight. High bars indicate symptoms you may have under-prioritized."),
        plotOutput("deadly_symptoms_plot", height = "500px")
      ),
      # Plot 2: Did the triage color match the urgency?
      card(
        card_header("Analysis: Wait Time vs. Reality"),
        p("This chart compares the patient's true urgency (Max Wait Time) against the Triage Color you assigned. Critical patients (low Max Wait Time) in the Green category are a major risk."),
        plotOutput("wait_time_plot", height = "500px")
      )
    ),
    # Data table of all patients
    card(
      card_header("Patient Data Log"),
      p("Detailed data for every patient in the simulation(s)."),
      DT::dataTableOutput("patient_table")
    )
  )
)


# --- 5. Server Logic ---
server <- function(input, output, session) {
  # Create a reactive list of symptom IDs for easier gathering of inputs
  symptom_input_ids <- reactive({
    setNames(
      str_to_lower(str_replace_all(SYMPTOMS_REFERENCE$symptom, " ", "_")),
      SYMPTOMS_REFERENCE$symptom
    )
  })

  # A reactive value to hold the results of the simulation.
  # We use a reactiveVal here so we can trigger the calculation inside an
  # observeEvent and store the result, which will then be used by the output
  # renderers. This will now store a list with the data and the plots.
  simulation_results <- reactiveVal(NULL)

  # This observer block runs the entire simulation when the button is clicked.
  observeEvent(input$run_simulation, {
    # Show a modal dialog to let the user know work is happening.
    showModal(modalDialog(
      title = "Processing...",
      div(
        class = "ambulance-parade",
        icon("ambulance", class = "ambulance-icon", style = "animation-delay: 0s;"),
        icon("ambulance", class = "ambulance-icon", style = "animation-delay: 0.5s;"),
        icon("ambulance", class = "ambulance-icon", style = "animation-delay: 1s;")
      ),
      "Running simulation and generating after action report. Please wait.",
      footer = NULL,
      easyClose = FALSE
    ))

    # Capture student's triage decisions into a tidy tibble
    student_triage_map <- tibble(
      symptom = names(symptom_input_ids()),
      assigned_color = purrr::map_chr(symptom_input_ids(), ~ req(input[[.x]]))
    )

    n_sims <- as.integer(input$n_simulations)
    sim_seed <- req(input$seed)

    # Use map_dfr to run the simulation N times and stack the results.
    results <- purrr::map_dfr(1:n_sims, ~ {
      set.seed(sim_seed + .x - 1)
      patients <- generate_patients(N_PATIENTS, SYMPTOMS_REFERENCE)
      patients_classified <- patients |>
        tidyr::unnest(symptoms) |>
        rename(symptom = symptoms) |>
        left_join(student_triage_map, by = "symptom") |>
        group_by(patient_id) |>
        summarise(
          patient_color = factor(assigned_color, levels = TRIAGE_LEVELS, ordered = TRUE) |> min(),
          max_wait_time = first(max_wait_time),
          symptoms = list(symptom)
        )
      ambulance_q <- patients_classified |>
        arrange(patient_color)
      inter_arrival_times <- rexp(N_PATIENTS * 2, rate = AMBULANCE_ARRIVAL_RATE)
      new_ambulance_arrival_times <- cumsum(inter_arrival_times)
      ambulance_availability <- c(rep(0, N_AMBULANCES), new_ambulance_arrival_times)
      time_waited_vec <- numeric(N_PATIENTS)
      for (i in 1:nrow(ambulance_q)) {
        next_free_time <- min(ambulance_availability)
        time_waited_vec[i] <- next_free_time
        ambulance_idx <- which.min(ambulance_availability)
        ambulance_availability[ambulance_idx] <- next_free_time + AMBULANCE_TRIP_TIME
      }
      ambulance_q$time_waited <- time_waited_vec
      ambulance_q |>
        mutate(
          result = if_else(time_waited > max_wait_time, "Life-Flight", "Standard"),
          simulation_run = .x
        ) |>
        select(
          simulation_run, patient_id, patient_color, time_waited,
          max_wait_time, result, symptoms
        )
    })

    # --- NOW, PRE-RENDER ALL PLOTS ---

    # Plot 1: Deadly Symptoms
    deadly_symptoms_data <- results |>
      tidyr::unnest(symptoms) |>
      rename(symptom = symptoms) |>
      group_by(symptom) |>
      summarise(pct_lifeflight = mean(result == "Life-Flight"), .groups = "drop")

    deadly_symptoms_plot <- ggplot(deadly_symptoms_data, aes(x = pct_lifeflight, y = fct_reorder(symptom, pct_lifeflight))) +
      geom_col(fill = "#e84351") +
      scale_x_continuous(labels = scales::percent) +
      labs(x = "Percent of Patients Requiring Life-Flight", y = "Symptom") +
      theme_minimal(base_size = 14)

    # Plot 2: Wait Time vs. Reality
    wait_time_plot_data <- results |>
      mutate(patient_color = factor(patient_color, levels = TRIAGE_LEVELS))

    wait_time_plot <- ggplot(wait_time_plot_data, aes(x = patient_color, y = max_wait_time, fill = patient_color)) +
      geom_boxplot() +
      scale_fill_manual(values = c("Red" = "#e84351", "Yellow" = "#f39c12", "Green" = "#00bc8c")) +
      labs(x = "Assigned Patient Triage Color", y = "Time Until Life-Flight Required (minutes)") +
      theme_minimal(base_size = 14) +
      theme(legend.position = "none")

    # Plot 3: Histogram (only for N > 1)
    lifeflight_histogram_plot <- NULL
    if (n_sims > 1) {
      lifeflights_per_run <- results |>
        group_by(simulation_run) |>
        summarise(n_flights = sum(result == "Life-Flight"), .groups = "drop")

      lifeflight_histogram_plot <- ggplot(lifeflights_per_run, aes(x = n_flights)) +
        geom_histogram(binwidth = 1, fill = "#00bc8c", color = "black") +
        labs(
          x = "Number of Life-Flights in a Single Simulation",
          y = "Frequency (Number of Simulations)",
          title = "Histogram of Life-Flight Outcomes"
        ) +
        theme_minimal(base_size = 14) +
        theme(plot.title = element_text(hjust = 0.5))
    }

    # Store all results and plots in our reactiveVal
    simulation_results(list(
      data = results,
      deadly_symptoms_plot = deadly_symptoms_plot,
      wait_time_plot = wait_time_plot,
      lifeflight_histogram = lifeflight_histogram_plot
    ))

    # Remove the modal and switch tabs
    removeModal()
    updateNavbarPage(session, "main_nav", selected = "After Action Report")
  })


  # --- Output Rendering ---

  # Render the summary metrics (Total Life-Flights or Average)
  output$results_summary_ui <- renderUI({
    req(simulation_results())

    results <- simulation_results()$data
    n_sims <- as.integer(input$n_simulations)

    if (n_sims == 1) {
      total_flights <- sum(results$result == "Life-Flight")
      card(
        card_header("Single Run Result"),
        h3(glue::glue("Total Life-Flights: {total_flights}"))
      )
    } else {
      lifeflights_per_run <- results |>
        filter(result == "Life-Flight") |>
        count(simulation_run)

      avg_flights <- mean(lifeflights_per_run$n)

      layout_columns(
        col_widths = c(4, 8),
        card(
          card_header("Average Result (100 Runs)"),
          h3(glue::glue("Average Life-Flights: {round(avg_flights, 2)}"))
        ),
        card(
          card_header("Distribution of Life-Flights"),
          plotOutput("lifeflight_histogram", height = "500px")
        )
      )
    }
  })

  # Render the histogram of life-flights for N=100 runs
  output$lifeflight_histogram <- renderPlot({
    req(simulation_results()$lifeflight_histogram)
    simulation_results()$lifeflight_histogram
  })

  # Render the "Deadly Symptoms" bar chart
  output$deadly_symptoms_plot <- renderPlot({
    req(simulation_results()$deadly_symptoms_plot)
    simulation_results()$deadly_symptoms_plot
  })

  # Render the "Wait Time vs. Reality" boxplot
  output$wait_time_plot <- renderPlot({
    req(simulation_results()$wait_time_plot)
    simulation_results()$wait_time_plot
  })

  # Render the detailed patient data table
  output$patient_table <- DT::renderDataTable({
    req(simulation_results()$data)
    # Pre-process the symptoms list-column to be a comma-separated string for display
    display_data <- simulation_results()$data |>
      mutate(symptoms = purrr::map_chr(symptoms, ~ paste(.x, collapse = ", ")))

    DT::datatable(
      display_data,
      options = list(pageLength = 10),
      rownames = FALSE,
      filter = "top"
    )
  })
}

# --- 6. Run the Application ---
shinyApp(ui, server)
