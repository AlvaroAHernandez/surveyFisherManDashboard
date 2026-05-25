# ============================================================================
# homogenize.R  ·  Homogenización de respuestas — Encuesta Pesquera UABCS
# ============================================================================
# Uso:
#   source("homogenize.R")          # carga funciones + reglas
#   df <- homogenizar_df(df)        # aplica al data.frame completo
#
# Las reglas se definen en json/homogenize_rules.json.
# Para inspeccionar qué tan diversas son las respuestas antes de normalizar:
#   inspeccionar_diversidad(df)
# ============================================================================

# ─── Operador null-coalesce (definido primero para uso interno) ─────────────
if (!exists("%||%", mode = "function"))
  `%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── Utilidades de texto ─────────────────────────────────────────────────────

# Elimina espacios sobrantes y colapsa espacios múltiples
limpiar_texto <- function(x) {
  if (is.na(x) || !is.character(x)) return(x)
  x <- trimws(x)
  gsub("\\s{2,}", " ", x)
}

# Versión para comparación: minúsculas + sin acentos
clave_comparacion <- function(x) {
  tolower(chartr("\u00e1\u00e9\u00ed\u00f3\u00fa\u00fc\u00c1\u00c9\u00cd\u00d3\u00da\u00dc\u00f1\u00d1",
                 "aeiouuAEIOUUnN", x))
}

# ─── Normalización Sí / No ───────────────────────────────────────────────────

ALIAS_SI <- c("si", "s\u00ed", "si", "SI", "S\u00cd", "yes", "YES", "1", "true",
              "TRUE", "s", "S", "verdadero")
ALIAS_NO <- c("no", "NO", "0", "false", "FALSE", "n", "N", "falso")

normalizar_si_no <- function(vec,
                              canonical_si = "S\u00ed",
                              canonical_no = "No",
                              aliases_si   = ALIAS_SI,
                              aliases_no   = ALIAS_NO) {
  resultado <- vapply(vec, limpiar_texto, character(1))
  clave     <- clave_comparacion(resultado)
  clv_si    <- clave_comparacion(aliases_si)
  clv_no    <- clave_comparacion(aliases_no)

  resultado[clave %in% clv_si] <- canonical_si
  resultado[clave %in% clv_no] <- canonical_no
  resultado
}

# ─── Motor de mapeo por sinónimos ────────────────────────────────────────────
# mapeo_list: lista de listas con campos "canonical" y "aliases"
aplicar_mapeo <- function(vec, mapeo_list) {
  resultado <- vapply(vec, limpiar_texto, character(1))
  clave     <- clave_comparacion(resultado)

  for (regla in mapeo_list) {
    canonical    <- regla$canonical
    clv_aliases  <- clave_comparacion(unlist(regla$aliases))
    idx          <- which(clave %in% clv_aliases)
    if (length(idx) > 0) {
      resultado[idx] <- canonical
      clave[idx]     <- clave_comparacion(canonical)   # actualiza clave para reglas posteriores
    }
  }
  resultado
}

# ─── Motor de reemplazos regex ───────────────────────────────────────────────
# regex_list: lista de listas con "patron" y "reemplazo"
aplicar_regex <- function(vec, regex_list) {
  resultado <- vec
  for (regla in regex_list) {
    idx <- grepl(regla$patron, resultado, ignore.case = TRUE, perl = TRUE)
    if (any(idx, na.rm = TRUE))
      resultado[idx] <- sub(regla$patron, regla$reemplazo,
                            resultado[idx], ignore.case = TRUE, perl = TRUE)
  }
  resultado
}

# ─── Homogenización de una columna ───────────────────────────────────────────
homogenizar_columna <- function(vec, reglas_col, si_no_cols_set = character(0), col_id = "") {
  resultado <- vec

  # 1. Normalización base (espacios)
  resultado <- vapply(resultado, limpiar_texto, character(1))

  # 2. Mapeo de sinónimos (si la columna tiene reglas)
  if (!is.null(reglas_col$mapeo))
    resultado <- aplicar_mapeo(resultado, reglas_col$mapeo)

  # 3. Regex
  if (!is.null(reglas_col$regex))
    resultado <- aplicar_regex(resultado, reglas_col$regex)

  # 4. Normalización Sí/No global (por defecto o por indicación en reglas)
  aplicar_sn <- isTRUE(reglas_col$si_no) || col_id %in% si_no_cols_set
  if (aplicar_sn)
    resultado <- normalizar_si_no(resultado)

  resultado
}

# ─── Homogenización del data.frame completo ──────────────────────────────────
homogenizar_df <- function(df, reglas = NULL) {
  if (is.null(reglas)) reglas <- HOMOGENIZE_RULES

  si_no_cols_set <- as.character(unlist(reglas$si_no_cols %||% list()))
  col_rules      <- reglas$reglas %||% list()

  for (col in names(df)) {
    if (!is.character(df[[col]])) next
    reglas_col <- col_rules[[col]] %||% list()
    df[[col]]  <- homogenizar_columna(df[[col]], reglas_col,
                                      si_no_cols_set = si_no_cols_set,
                                      col_id = col)
  }
  df
}

# ─── Carga de reglas desde JSON ──────────────────────────────────────────────
cargar_reglas_homogenizacion <- function(ruta = "json/homogenize_rules.json") {
  tryCatch(
    jsonlite::read_json(ruta, simplifyVector = FALSE),
    error = function(e) {
      message("homogenize.R: archivo de reglas no encontrado (", ruta, ").",
              " Usando solo normalización base Sí/No y espacios.")
      list()
    }
  )
}

# ─── Diagnóstico: diversidad de respuestas ───────────────────────────────────
# Imprime, para cada columna de preguntas, sus valores únicos antes/después
# de normalizar. Útil para descubrir nuevas variantes a añadir en el JSON.
#
# Uso desde consola:
#   source("homogenize.R")
#   df_raw <- cargar_desde_firebase()    # o cualquier data.frame
#   inspeccionar_diversidad(df_raw, max_uniq = 20)
inspeccionar_diversidad <- function(df, max_uniq = 20, aplicar = TRUE) {
  q_cols <- names(df)[vapply(names(df), function(x) grepl("^[0-9]+\\.", x), logical(1))]
  if (length(q_cols) == 0) {
    cat("No se encontraron columnas de preguntas (ej. '1.1', '3.2').\n")
    return(invisible(NULL))
  }

  df_hom <- if (aplicar) homogenizar_df(df) else df

  for (col in q_cols) {
    raw_uniq <- sort(unique(na.omit(as.character(df[[col]]))))
    hom_uniq <- sort(unique(na.omit(as.character(df_hom[[col]]))))

    if (length(raw_uniq) < 2 || length(raw_uniq) > max_uniq) next
    cambios <- length(raw_uniq) - length(hom_uniq)

    cat(sprintf("\n[%s]  %d únicos → %d únicos  (%s)\n",
                col, length(raw_uniq), length(hom_uniq),
                if (cambios > 0) sprintf("↓ %d consolidados", cambios) else "sin cambios"))

    if (cambios > 0) {
      # Muestra solo los que cambiaron
      antes <- as.character(df[[col]])
      despues <- as.character(df_hom[[col]])
      for (i in seq_along(antes)) {
        if (!is.na(antes[i]) && !is.na(despues[i]) && antes[i] != despues[i]) {
          cat(sprintf("  \"%s\"  →  \"%s\"\n", antes[i], despues[i]))
        }
      }
    } else {
      for (v in hom_uniq) cat(sprintf("  - \"%s\"\n", v))
    }
  }
  invisible(df_hom)
}

# ─── Inicialización ──────────────────────────────────────────────────────────
HOMOGENIZE_RULES <- cargar_reglas_homogenizacion()
