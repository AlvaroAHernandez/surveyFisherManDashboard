# Script de instalación automática de dependencias para ShinyApp
# Ejecutar: Rscript install_dependencies.R
# O en RStudio: source("install_dependencies.R")

cat("📦 Instalando dependencias para ShinyApp de Encuestas Pesqueras...\n")
cat(paste0(rep("=", 71), collapse = ""), "\n")

# Lista de paquetes necesarios
pkgs <- c(
  "shiny",           # Framework web
  "shinydashboard",  # Componentes dashboard
  "shinyjs",         # Interactividad JavaScript
  "tidyverse",       # Data manipulation (dplyr, ggplot2, etc.)
  "plotly",          # Gráficos interactivos
  "jsonlite",        # Lectura de JSON
  "readr",           # Lectura de CSV
  "DT"               # DataTables interactivas
)

# Función para instalar paquete si no existe
install_if_missing <- function(pkg) {
  if (!require(pkg, character.only = TRUE)) {
    cat("  📥 Instalando", pkg, "...\n")
    install.packages(pkg, dependencies = TRUE)
    cat("  ✅ ", pkg, "instalado correctamente\n")
  } else {
    cat("  ✓ ", pkg, "ya está instalado\n")
  }
}

# Instalar cada paquete
cat("\nVerificando e instalando paquetes necesarios:\n")
lapply(pkgs, install_if_missing)

cat(paste0("\n", paste0(rep("=", 71), collapse = ""), "\n"))
cat("✨ Instalación completada!\n")
cat("Ahora puedes ejecutar la app con:\n")
cat("  shiny::runApp('shiny_app.R')\n\n")
