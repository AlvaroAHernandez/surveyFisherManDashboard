# Test de compilación - verifica que el código R es válido

cat("Compilando shiny_app.R...\n")

tryCatch({
  # Cargar librerías necesarias
  suppressWarnings(suppressPackageStartupMessages({
    library(shiny)
    library(shinydashboard)
    library(shinyjs)
    library(tidyverse)
    library(plotly)
    library(jsonlite)
    library(readr)
    library(DT)
  }))

  # Cargar archivo
  source("shiny_app.R")

  cat("\n✅ Compilación exitosa!\n")
  cat("La app está lista para ejecutarse.\n")
  cat("\nEjecuta: shiny::runApp('shiny_app.R')\n\n")

}, error = function(e) {
  cat("\n❌ Error de compilación:\n")
  cat(sprintf("  %s\n\n", e$message))
})
