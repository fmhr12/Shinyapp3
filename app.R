library(shiny)
library(shinythemes)
library(survival)
library(riskRegression)
library(ggplot2)
library(prodlim)
library(plotly)    # For interactive plots

# -----------------------
# 1. Load Final Model
# -----------------------
saved_model_path <- "final_fg_model.rds"
final_model <- readRDS(saved_model_path)

mean_cif_data_overall <- readRDS("mean_cif_data_all.rds")
mean_cif_data_pos     <- readRDS("mean_cif_data_ORN_positive.rds")
mean_cif_data_neg     <- readRDS("mean_cif_data_ORN_negative.rds")


feature_cols <- c("Insurance_Type", "Node", "Periodontal_Grading",
                  "Disease_Site_Merged_2", "Age", 
                  "Smoking_Pack_per_Year", "T",
                  "Number_Teeth_before_Extraction", "RT_Dose", "D10cc")

# -----------------------
# UI
# -----------------------
ui <- fluidPage(
  theme = shinytheme("flatly"),
  
  titlePanel("ORN Prognosis Model"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Enter Predictor Values"),
      
      # 1. Tumor Site
      selectInput("Disease_Site_Merged_2", "Tumor Site",
                  choices = list("Others" = "0", "Oropharynx" = "1", "Oral Cavity" = "2"),
                  selected = "2"),
      
      # 2. D10cc (Gy)
      numericInput("D10cc", "D10cc (Gy)", value = 55, min = 0, max = 100),
      
      # 3. Periodontal Grading
      selectInput("Periodontal_Grading", "Periodontal Grading",
                  choices = list("0" = "0", "I" = "1", "II" = "2", "III" = "3", "IV" = "4"),
                  selected = "3"),
      
      # 4. Node Status
      selectInput("Node", "Node Status",
                  choices = list("N0" = "0", "N1" = "1", "N2" = "2", "N3" = "3"),
                  selected = "2"),
      
      # 5. Number of Teeth Before Extraction
      numericInput("Number_Teeth_before_Extraction", "Number of Teeth Before Extraction", 
                   value = 20, min = 0, max = 32),
      
      # 6. Smoking Pack-Year
      numericInput("Smoking_Pack_per_Year", "Smoking Pack-Year", value = 50, min = 0, max = 200),
      
      # 7. Insurance Type
      selectInput("Insurance_Type", "Insurance Type",
                  choices = list("No Insurance" = "0", "Private" = "1", "Public" = "2"),
                  selected = "0"),
      
      # 8. Tumor Status
      selectInput("T", "Tumor Status",
                  choices = list("T0" = "0", "T1" = "1", "T2" = "2", "T3" = "3", "T4" = "4"),
                  selected = "2"),
      
      # 9. Age
      numericInput("Age", "Age", value = 60, min = 0, max = 120),
      
      # 10. RT Total Prescribed Dose
      numericInput("RT_Dose", "RT Total Prescribed Dose", value = 66, min = 0, max = 80),
      
      textInput("time_points_interest", "Time Points (comma-separated)", value = "60"),
      
      # Use a checkbox group to toggle reference curves:
      checkboxGroupInput("showReference", "Show Reference (Average CIF) Options", 
                         choices = list("Average Overall in PMCC" = "overall", 
                                        "Average ORN Positive in PMCC" = "pos", 
                                        "Average ORN Negative in PMCC" = "neg"),
                         selected = "overall"),
      
      actionButton("predictBtn", "Predict"),
      br(),
      helpText("Click the button to generate the CIF curve and predictions.")
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Results",
          h4("CIF Curve"),
          plotlyOutput("plotCIF"),
          br(),
          h4("CIF Values at Requested Time Points"),
          tableOutput("cifValues")
        )
      )
    )
  )
)

# -----------------------
# SERVER
# -----------------------
server <- function(input, output, session) {
  
  # Create a 1-row data frame from user inputs in the same order as the UI
  newdata_reactive <- reactive({
    data.frame(
      Disease_Site_Merged_2 = factor(input$Disease_Site_Merged_2, levels = c("0", "1", "2")),
      D10cc = as.numeric(input$D10cc),
      Periodontal_Grading = factor(input$Periodontal_Grading, levels = c("0", "1", "2", "3", "4")),
      Node = factor(input$Node, levels = c("0", "1", "2", "3")),
      Number_Teeth_before_Extraction = as.numeric(input$Number_Teeth_before_Extraction),
      Smoking_Pack_per_Year = as.numeric(input$Smoking_Pack_per_Year),
      Insurance_Type = factor(input$Insurance_Type, levels = c("0", "1", "2")),
      T = factor(input$T, levels = c("0", "1", "2", "3", "4")),
      Age = as.numeric(input$Age),
      RT_Dose = as.numeric(input$RT_Dose)
    )
  })
  
  observeEvent(input$predictBtn, {
    # 1. Predict & Plot CIF curve for the individual
    one_indiv <- newdata_reactive()
    time_grid <- seq(0, 114, by = 1)
    indiv_cif <- predictRisk(final_model, newdata = one_indiv, times = time_grid, cause = 1)
    cif_values <- as.numeric(indiv_cif[1, ])
    
    output$plotCIF <- renderPlotly({
      df_plot <- data.frame(
        Time = time_grid,
        CIF = round(cif_values, 3)
      )
      p <- ggplot(df_plot, aes(x = Time, y = CIF)) +
        geom_line(color = "blue") +
        geom_point(aes(text = paste0("Time: ", Time, "\nCIF: ", sprintf('%.3f', CIF))),
                   color = "blue", size = 1) +
        theme_minimal() +
        labs(x = "Time (months)", y = "CIF")
      
      # Add reference curves based on selected options
      if("overall" %in% input$showReference) {
        p <- p +
          geom_line(data = mean_cif_data_overall, aes(x = Time, y = MeanCIF),
                    color = "red", linetype = "dashed") +
          geom_point(data = mean_cif_data_overall, aes(x = Time, y = MeanCIF,
                                                       text = paste0("Time: ", Time, "\nOverall CIF: ", sprintf('%.3f', MeanCIF))),
                     color = "red", size = 1)
      }
      if("pos" %in% input$showReference) {
        p <- p +
          geom_line(data = mean_cif_data_pos, aes(x = Time, y = MeanCIF),
                    color = "orange", linetype = "dotted") +
          geom_point(data = mean_cif_data_pos, aes(x = Time, y = MeanCIF,
                                                   text = paste0("Time: ", Time, "\nORN Positive CIF: ", sprintf('%.3f', MeanCIF))),
                     color = "orange", size = 1)
      }
      if("neg" %in% input$showReference) {
        p <- p +
          geom_line(data = mean_cif_data_neg, aes(x = Time, y = MeanCIF),
                    color = "green", linetype = "dotdash") +
          geom_point(data = mean_cif_data_neg, aes(x = Time, y = MeanCIF,
                                                   text = paste0("Time: ", Time, "\nORN Negative CIF: ", sprintf('%.3f', MeanCIF))),
                     color = "green", size = 1)
      }
      
      ggplotly(p, tooltip = "text")
    })
    
    # 2. Show CIF values at user-requested times in a table
    user_times_vec <- as.numeric(trimws(strsplit(input$time_points_interest, ",")[[1]]))
    user_times_vec <- user_times_vec[!is.na(user_times_vec)]
    if (length(user_times_vec) == 0) user_times_vec <- c(60, 114)
    indiv_cif_interest <- predictRisk(final_model, newdata = one_indiv, 
                                      times = user_times_vec, cause = 1)
    
    output$cifValues <- renderTable({
      data.frame(
        Time = user_times_vec,
        CIF = sprintf("%.3f", as.numeric(indiv_cif_interest))
      )
    }, digits = 0, align = 'c')
  })
}

if (interactive()) {
  shinyApp(ui = ui, server = server)
} else {
  # In a production (non-interactive) environment, use the PORT provided by Render.
  shiny::runApp(list(ui = ui, server = server), 
                host = "0.0.0.0", 
                port = as.numeric(Sys.getenv("PORT", 10000)))
}


