#
# Mass Casualty Triage Simulation - R Shiny App
# A Data Science Education Activity
#
# Teaches concepts of prioritization, resource allocation, and statistical thinking
# using the START (Simple Triage And Rapid Treatment) framework.
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
library(ggforce)

# --- 2. Data and Constants ---

# A master tibble of all possible symptoms (realistic, START-style clinical signs).
# mean_wait: Average time (minutes) after the incident before this condition becomes
#            fatal if the patient is not evacuated and treated.
# sd_wait: Standard deviation, representing patient-to-patient variability.
# Severity is intentionally NOT obvious from the sign alone -- students must run the
# simulation to discover which signs are actually the most time-critical.

multiplier <- 1
SYMPTOMS_REFERENCE <- tibble::tribble(
  ~symptom, ~mean_wait, ~sd_wait, ~default_color,
  # Unsalvageable in the field (extremely low wait times -- candidates for "Black")
  "Absent Or Agonal Breathing", 5, 1.5, "Green",
  # Critical (low wait times -- need transport soon to survive)
  "No Palpable Radial Pulse", 12, 3, "Green",
  "Respiratory Rate Over 30 Per Minute", 20, 5, "Green",
  "Unable To Follow Simple Commands", 25, 6, "Green",
  "Capillary Refill Over 2 Seconds", 35, 8, "Green",
  # Moderate (can wait longer, but not indefinitely)
  "Uncontrolled Bleeding, Now Controlled", 60, 15, "Green",
  "Open Or Deformed Fracture", 100, 20, "Green",
  "Disoriented But Answers Questions", 150, 30, "Green",
  # Minor / walking wounded (high wait times)
  "Ambulatory With Minor Lacerations", 240, 40, "Green",
  "Superficial Burns, Ambulatory", 300, 50, "Green"
) |>
  mutate(
    mean_wait = mean_wait * multiplier,
    sd_wait = sd_wait * multiplier
  ) |>
  arrange(symptom) # Sort alphabetically for the UI

# Simulation constants
N_PATIENTS <- 50
N_AMBULANCES <- 10
AMBULANCE_TRIP_TIME <- 15 # minutes for a round trip
AMBULANCE_ARRIVAL_RATE <- 0.1 # Average number of new ambulances arriving per minute
# Minutes before the first ambulances can reach the scene, assess, and load a patient.
# This creates a hard floor under every patient's wait time -- it's what makes some
# symptoms genuinely unsalvageable ("Black") no matter how they're triaged.
SCENE_ARRIVAL_DELAY <- 8
# Severity ranking used to classify a patient (most severe symptom wins).
# Black outranks every other color: one Black-tagged symptom makes the whole patient
# "Expectant" regardless of their other symptoms.
TRIAGE_LEVELS <- c("Black", "Red", "Yellow", "Green")
# Colors offered to students, in the conventional order triage tags are read.
TRIAGE_CHOICES <- c("Red", "Yellow", "Green", "Black")
# Priority order for the ambulance queue. Black patients are Expectant and are
# never assigned an ambulance, so they're excluded here entirely.
TRANSPORT_PRIORITY <- c("Red", "Yellow", "Green")

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
        numericInput("seed", "Simulation Seed", value = sample(1:100000, 1), min = 1),
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
        p(
          class = "text-muted",
          strong("Black (Expectant)"),
          " means the patient will NOT be sent an ambulance at all -- reserve it for ",
          "symptoms so severe that transport wouldn't save the patient anyway."
        ),
        # Dynamically generate select inputs for each symptom
        !!!purrr::pmap(list(SYMPTOMS_REFERENCE$symptom, SYMPTOMS_REFERENCE$default_color), ~ {
          # Create a sanitized ID for the input control
          input_id <- str_to_lower(str_replace_all(..1, " ", "_"))
          selectInput(
            inputId = input_id,
            label = ..1,
            choices = TRIAGE_CHOICES,
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
      # Plot 1: Which symptoms led to deaths?
      card(
        card_header("Analysis: The Deadly Symptoms"),
        p("This chart shows the percentage of patients with a given symptom who died."),
        plotOutput("deadly_symptoms_plot", height = "500px")
      ),
      # Plot 2: Did the triage color match the urgency?
      card(
        card_header("Analysis: Triage vs. Transport Time"),
        p("This chart compares the time a patient waited for transport against the Triage Color you assigned. Use the filters to see how outcome and symptom relate to wait time. (Black/Expectant patients are never transported, so they have no wait time and don't appear here.)"),
        layout_columns(
          col_widths = c(6, 6),
          radioButtons(
            "outcome_filter",
            "Filter by Outcome:",
            choices = c("Both", "Died", "Survived"),
            selected = "Both",
            inline = TRUE
          ),
          selectInput(
            "symptom_filter",
            "Filter by Symptom:",
            choices = c("All Symptoms" = "All", SYMPTOMS_REFERENCE$symptom),
            selected = "All"
          )
        ),
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
        ) |>
        ungroup()

      # Black (Expectant) patients are never sent an ambulance. Split them out
      # before the queueing logic so they don't consume an ambulance slot.
      expectant_patients <- patients_classified |>
        filter(patient_color == "Black") |>
        mutate(patient_color = as.character(patient_color), time_waited = NA_real_)

      ambulance_q <- patients_classified |>
        filter(patient_color != "Black") |>
        mutate(patient_color = factor(patient_color, levels = TRANSPORT_PRIORITY, ordered = TRUE)) |>
        arrange(patient_color)
      n_transport <- nrow(ambulance_q)

      inter_arrival_times <- rexp(N_PATIENTS * 2, rate = AMBULANCE_ARRIVAL_RATE)
      new_ambulance_arrival_times <- cumsum(inter_arrival_times)
      # Every ambulance -- including the first N_AMBULANCES already dispatched --
      # is floored at SCENE_ARRIVAL_DELAY: the minimum time to reach, assess, and
      # load a patient after the incident is called in.
      ambulance_availability <- SCENE_ARRIVAL_DELAY +
        c(rep(0, N_AMBULANCES), new_ambulance_arrival_times)
      time_waited_vec <- numeric(n_transport)
      if (n_transport > 0) {
        for (i in 1:n_transport) {
          next_free_time <- min(ambulance_availability)
          time_waited_vec[i] <- next_free_time
          ambulance_idx <- which.min(ambulance_availability)
          ambulance_availability[ambulance_idx] <- next_free_time + rexp(1, rate = 1 / AMBULANCE_TRIP_TIME)
        }
      }
      ambulance_q$time_waited <- time_waited_vec

      ambulance_q |>
        mutate(
          patient_color = as.character(patient_color),
          result = if_else(time_waited > max_wait_time, "Died", "Survived"),
          simulation_run = .x
        ) |>
        bind_rows(
          expectant_patients |>
            mutate(result = "Died", simulation_run = .x)
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
      summarise(pct_died = mean(result == "Died"), .groups = "drop")

    deadly_symptoms_plot <- ggplot(deadly_symptoms_data, aes(x = pct_died, y = fct_reorder(symptom, pct_died))) +
      geom_col(fill = "#e84351") +
      scale_x_continuous(labels = scales::percent) +
      labs(x = "Percent of Patients Who Died", y = "Symptom") +
      theme_minimal(base_size = 14)

    # Plot 3: Histogram (only for N > 1)
    death_histogram_plot <- NULL
    if (n_sims > 1) {
      deaths_per_run <- results |>
        group_by(simulation_run) |>
        summarise(n_deaths = sum(result == "Died"), .groups = "drop")

      death_histogram_plot <- ggplot(deaths_per_run, aes(x = n_deaths)) +
        geom_histogram(binwidth = 1, fill = "#00bc8c", color = "black") +
        labs(
          x = "Number of Deaths in a Single Simulation",
          y = "Frequency (Number of Simulations)",
          title = "Histogram of Death Outcomes"
        ) +
        theme_minimal(base_size = 14) +
        theme(plot.title = element_text(hjust = 0.5))
    }

    # Store all results and plots in our reactiveVal
    simulation_results(list(
      data = results,
      deadly_symptoms_plot = deadly_symptoms_plot,
      death_histogram = death_histogram_plot
    ))

    # Remove the modal and switch tabs
    removeModal()
    updateNavbarPage(session, "main_nav", selected = "After Action Report")
  })


  # --- Output Rendering ---

  # Render the summary metrics (Total Deaths or Average)
  output$results_summary_ui <- renderUI({
    req(simulation_results())

    results <- simulation_results()$data
    n_sims <- as.integer(input$n_simulations)

    if (n_sims == 1) {
      total_deaths <- sum(results$result == "Died")
      card(
        card_header("Single Run Result"),
        h3(glue::glue("Total Deaths: {total_deaths}"))
      )
    } else {
      deaths_per_run <- results |>
        group_by(simulation_run) |>
        summarise(n_deaths = sum(result == "Died"), .groups = "drop")

      avg_deaths <- mean(deaths_per_run$n_deaths)
      median_deaths <- median(deaths_per_run$n_deaths)
      min_deaths <- min(deaths_per_run$n_deaths)
      max_deaths <- max(deaths_per_run$n_deaths)

      layout_columns(
        col_widths = c(4, 8),
        card(
          card_header("Statistical Results (100 Runs)"),
          h5(glue::glue("Average Deaths: {round(avg_deaths, 2)}")),
          h5(glue::glue("Min Deaths: {min_deaths}")),
          h5(glue::glue("Median Deaths: {median_deaths}")),
          h5(glue::glue("Max Deaths: {max_deaths}"))
        ),
        card(
          card_header("Distribution of Deaths"),
          plotOutput("death_histogram", height = "500px")
        )
      )
    }
  })

  # Render the histogram of deaths for N=100 runs
  output$death_histogram <- renderPlot({
    req(simulation_results()$death_histogram)
    simulation_results()$death_histogram
  })

  # Render the "Deadly Symptoms" bar chart
  output$deadly_symptoms_plot <- renderPlot({
    req(simulation_results()$deadly_symptoms_plot)
    simulation_results()$deadly_symptoms_plot
  })

  # Render the "Wait Time vs. Reality" plot.
  # Black/Expectant patients have no time_waited (they were never transported),
  # so they naturally drop out of this plot -- it only covers transported patients.
  output$wait_time_plot <- renderPlot({
    req(simulation_results()$data)

    plot_data <- simulation_results()$data

    # Filter data based on the outcome filter input
    if (input$outcome_filter != "Both") {
      plot_data <- plot_data |>
        filter(result == input$outcome_filter)
    }

    # Filter data based on the symptom filter input (a patient can have 1-3
    # symptoms, so we keep any patient whose symptom list contains the pick)
    if (input$symptom_filter != "All") {
      plot_data <- plot_data |>
        filter(purrr::map_lgl(symptoms, ~ input$symptom_filter %in% .x))
    }

    plot_data <- plot_data |>
      filter(!is.na(time_waited))

    # Ensure there's data to plot after filtering
    validate(
      need(nrow(plot_data) > 0, "No data available for this filter selection.")
    )

    plot_data <- plot_data |>
      mutate(patient_color = factor(patient_color, levels = TRIAGE_LEVELS))

    ggplot(plot_data, aes(x = patient_color, y = time_waited, color = patient_color)) +
      # geom_boxplot(fill = "white") +
      geom_sina(alpha = 0.5, jitter_y = FALSE, scale = "width") +
      scale_color_manual(values = c(
        "Red" = "#e84351", "Yellow" = "#f39c12",
        "Green" = "#00bc8c", "Black" = "#3a3a3a"
      )) +
      labs(
        x = "Assigned Patient Triage Color",
        y = "Time Waited for Transport (minutes)"
      ) +
      theme_minimal(base_size = 14) +
      theme(legend.position = "none")
  })

  # Render the detailed patient data table
  output$patient_table <- DT::renderDataTable({
    req(simulation_results()$data)
    # Pre-process the symptoms list-column to be a comma-separated string for display
    display_data <- simulation_results()$data |>
      select(-max_wait_time) |> 
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
