## download_and_homogenize.R
## Descarga Firebase → aplica homogenización → guarda CSV + reporte de cambios
## Ejecutar desde la raíz del proyecto:
##   Rscript download_and_homogenize.R

suppressMessages({
  library(httr); library(openssl); library(jsonlite); library(dplyr)
})

cat("=== Descargando datos de Firebase ===\n")

# ── Reutiliza las funciones de shiny_app.R sin lanzar la app ─────────────────
source_lines <- readLines("shiny_app.R")
# Toma todo hasta la primera línea de la sección UI (empieza con "ui <- ")
end_idx <- min(grep("^ui\\s*<-", source_lines)) - 1
eval(parse(text = paste(source_lines[1:end_idx], collapse = "\n")),
     envir = .GlobalEnv)

df_raw <- cargar_desde_firebase()
cat("Filas:", nrow(df_raw), "  Columnas:", ncol(df_raw), "\n\n")

# ── Aplica homogenización ─────────────────────────────────────────────────────
cat("=== Aplicando homogenización ===\n")
df_hom <- homogenizar_df(df_raw)

# ── Reporte de cambios ────────────────────────────────────────────────────────
cat("\n=== Reporte de cambios por columna ===\n")
q_cols <- names(df_raw)[vapply(names(df_raw), function(x) grepl("^[0-9]+\\.", x), logical(1))]
total_cambios <- 0L

for (col in q_cols) {
  raw_vals <- as.character(df_raw[[col]])
  hom_vals <- as.character(df_hom[[col]])
  dif      <- which(!is.na(raw_vals) & raw_vals != hom_vals)
  if (length(dif) == 0) next
  total_cambios <- total_cambios + length(dif)
  cat(sprintf("\n[%s] — %d celdas modificadas:\n", col, length(dif)))
  # Muestra pares únicos de (antes → después)
  pares <- unique(data.frame(antes = raw_vals[dif], despues = hom_vals[dif],
                              stringsAsFactors = FALSE))
  for (i in seq_len(nrow(pares)))
    cat(sprintf('  "%s"  →  "%s"\n', pares$antes[i], pares$despues[i]))
}
cat(sprintf("\nTotal de celdas homogenizadas: %d\n", total_cambios))

# ── Guarda CSV ────────────────────────────────────────────────────────────────
out_file <- sprintf("data_homogenized_%s.csv", format(Sys.Date(), "%Y%m%d"))
write.csv(df_hom, out_file, row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("\n=== Guardado: %s ===\n", out_file))
