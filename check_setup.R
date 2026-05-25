# Script de verificación de setup para ShinyApp
# Ejecutar: Rscript check_setup.R

cat("\n")
cat(paste0(rep("=", 71), collapse = ""), "\n")
cat("  VERIFICACIÓN DE SETUP - ShinyApp Pesquero\n")
cat(paste0(rep("=", 71), collapse = ""), "\n\n")

# Verificar paquetes
pkgs_required <- c(
  "shiny", "shinydashboard", "shinyjs", "tidyverse",
  "plotly", "jsonlite", "readr", "DT"
)

missing_pkgs <- c()

for (pkg in pkgs_required) {
  if (require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat(sprintf("  ✓ %s\n", pkg))
  } else {
    cat(sprintf("  ✗ %s (NO INSTALADO)\n", pkg))
    missing_pkgs <- c(missing_pkgs, pkg)
  }
}

cat("\n")

if (length(missing_pkgs) > 0) {
  cat(sprintf("⚠️  Faltan %d paquete(s). Instalando...\n\n", length(missing_pkgs)))
  install.packages(missing_pkgs)
  cat("\n✅ Instalación completada.\n")
} else {
  cat("✅ Todos los paquetes necesarios están instalados.\n")
}

cat("\nVerificando archivos necesarios:\n")

archivos_requeridos <- c(
  "shiny_app.R",
  "json/survey.json",
  "geopoint.csv"
)

for (archivo in archivos_requeridos) {
  if (file.exists(archivo)) {
    cat(sprintf("  ✓ %s\n", archivo))
  } else {
    cat(sprintf("  ✗ %s (NO ENCONTRADO)\n", archivo))
  }
}

cat(paste0("\n", paste0(rep("=", 71), collapse = ""), "\n"))
cat("Para iniciar la app, ejecuta:\n")
cat("  shiny::runApp('shiny_app.R')\n\n")
