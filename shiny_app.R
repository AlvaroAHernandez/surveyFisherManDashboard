library(shiny)
library(shinydashboard)
library(tidyverse)
library(plotly)
library(readr)
library(DT)
library(httr)
library(openssl)
library(jsonlite)

# ─── Módulo de homogenización (debe cargarse antes de los datos) ─────────────
source("homogenize.R")

# Colores UABCS
UABCS_COLORS <- list(
  azul = "#009FD4",
  azul_marino = "#00497E",
  azul_suave = "#E3F4FB",
  amarillo = "#FFD100",
  gris = "#4A5568"
)

PLOTLY_BG <- "rgba(0,0,0,0)"   # fondo totalmente transparente

# =================== AUTENTICACIÓN FIREBASE ===================

FIREBASE_WEB_API_KEY <- "AIzaSyCoA7X87ZaLLmVx0xVWlivb1eG7igRoZws"

autenticar_usuario <- function(email, password) {
  url <- paste0(
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=",
    FIREBASE_WEB_API_KEY
  )
  tryCatch({
    resp <- httr::POST(
      url,
      body   = jsonlite::toJSON(
        list(email = email, password = password, returnSecureToken = TRUE),
        auto_unbox = TRUE
      ),
      httr::content_type_json(),
      httr::timeout(10)
    )
    data <- httr::content(resp, as = "parsed")
    if (httr::status_code(resp) == 200) {
      list(ok = TRUE, email = data$email, uid = data$localId)
    } else {
      error_msg <- data$error$message %||% "ERROR_DESCONOCIDO"
      mensajes <- list(
        EMAIL_NOT_FOUND             = "El correo no está registrado.",
        INVALID_PASSWORD            = "Contraseña incorrecta.",
        USER_DISABLED               = "Esta cuenta ha sido deshabilitada.",
        INVALID_LOGIN_CREDENTIALS   = "Correo o contraseña incorrectos.",
        TOO_MANY_ATTEMPTS_TRY_LATER = "Demasiados intentos fallidos. Intenta más tarde."
      )
      list(ok = FALSE, error = mensajes[[error_msg]] %||% paste("Error:", error_msg))
    }
  }, error = function(e) {
    list(ok = FALSE, error = paste("Error de conexión:", conditionMessage(e)))
  })
}

# =================== CONFIGURACIÓN FIREBASE ===================

CRED_PATH           <- "surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json"
FIREBASE_COLLECTION <- "survey_responses"
.fb_env             <- new.env(parent = emptyenv())   # cache de token

base64url_encode <- function(x) {
  if (is.character(x)) x <- charToRaw(x)
  b64 <- gsub("[[:space:]]", "", openssl::base64_encode(x))
  sub("=+$", "", chartr("+/", "-_", b64))
}

obtener_token_firebase <- function() {
  now <- as.integer(Sys.time())
  if (!is.null(.fb_env$token) && !is.null(.fb_env$expiry) && now < .fb_env$expiry) {
    return(.fb_env$token)
  }
  cred    <- jsonlite::fromJSON(CRED_PATH)
  header  <- base64url_encode('{"alg":"RS256","typ":"JWT"}')
  payload <- base64url_encode(jsonlite::toJSON(list(
    iss   = cred$client_email,
    sub   = cred$client_email,
    aud   = "https://oauth2.googleapis.com/token",
    iat   = now,
    exp   = now + 3600L,
    scope = "https://www.googleapis.com/auth/datastore"
  ), auto_unbox = TRUE))
  signing_input <- paste0(header, ".", payload)
  key  <- openssl::read_key(gsub("\\\\n", "\n", cred$private_key))
  sig  <- openssl::signature_create(charToRaw(signing_input), hash = openssl::sha256, key = key)
  jwt  <- paste0(signing_input, ".", base64url_encode(sig))
  resp <- httr::POST(
    "https://oauth2.googleapis.com/token",
    body   = list(grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion = jwt),
    encode = "form"
  )
  if (httr::http_error(resp)) stop("Auth error: ", httr::content(resp, as = "text"))
  token          <- httr::content(resp)$access_token
  .fb_env$token  <- token
  .fb_env$expiry <- now + 3500L
  token
}

parse_firestore_value <- function(v) {
  if (!is.null(v$stringValue))    return(v$stringValue)
  if (!is.null(v$integerValue))   return(v$integerValue)   # kept as string; normalised later
  if (!is.null(v$doubleValue))    return(as.numeric(v$doubleValue))
  if (!is.null(v$booleanValue))   return(v$booleanValue)
  if (!is.null(v$timestampValue)) return(v$timestampValue)
  if (!is.null(v$mapValue))       return(lapply(v$mapValue$fields, parse_firestore_value))
  if (!is.null(v$arrayValue)) {
    vals <- v$arrayValue$values
    return(if (is.null(vals)) list() else lapply(vals, parse_firestore_value))
  }
  NA
}

parse_firestore_doc <- function(doc) {
  result <- list()
  for (fname in names(doc$fields)) {
    val <- parse_firestore_value(doc$fields[[fname]])
    if (fname == "responses" && is.list(val)) {
      for (k in names(val)) result[[k]] <- val[[k]]
    } else {
      result[[fname]] <- val
    }
  }
  result
}

cargar_desde_firebase <- function() {
  if (!file.exists(CRED_PATH)) return(NULL)
  token      <- obtener_token_firebase()
  project_id <- jsonlite::fromJSON(CRED_PATH)$project_id
  base_url   <- sprintf(
    "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s",
    project_id, FIREBASE_COLLECTION
  )
  all_docs   <- list()
  page_token <- NULL
  repeat {
    url  <- if (is.null(page_token)) base_url else paste0(base_url, "?pageToken=", page_token)
    resp <- httr::GET(url, httr::add_headers(Authorization = paste("Bearer", token)))
    if (httr::http_error(resp)) break
    data <- httr::content(resp, as = "parsed")
    if (!is.null(data$documents)) all_docs <- c(all_docs, data$documents)
    if (is.null(data$nextPageToken)) break
    page_token <- data$nextPageToken
  }
  if (length(all_docs) == 0) return(data.frame())
  rows <- lapply(all_docs, parse_firestore_doc)
  dplyr::bind_rows(lapply(rows, function(r) {
    r_proc <- lapply(names(r), function(nm) {
      v <- r[[nm]]
      if (!is.list(v)) {
        return(if (length(v) == 1) as.character(v) else NA_character_)
      }
      # Detecta mapa especie→meses (4.7.4): cada valor es list() o list de chars
      es_scalar_o_lista_chars <- function(x) {
        if (length(x) == 0) return(TRUE)
        if (is.character(x)) return(TRUE)
        if (is.list(x)) return(all(vapply(x, function(i) is.character(i) && length(i) == 1, logical(1))))
        FALSE
      }
      es_mapa_meses <- all(vapply(v, es_scalar_o_lista_chars, logical(1)))
      if (es_mapa_meses) {
        con_meses <- Filter(function(meses) length(meses) > 0, v)
        con_meses <- lapply(con_meses, function(meses) as.character(unlist(meses)))
        if (length(con_meses) > 0)
          return(as.character(jsonlite::toJSON(con_meses, auto_unbox = FALSE)))
      }
      NA_character_
    })
    names(r_proc) <- names(r)
    as.data.frame(r_proc, stringsAsFactors = FALSE, check.names = FALSE)
  }))
}

# =================== SURVEY JSON / ETIQUETAS ===================

# ─── Operador %||% ──────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── Etiquetas del cuestionario ─────────────────────────────────────────────
cargar_encuesta_json <- function() {
  tryCatch({
    s <- jsonlite::read_json("json/survey.json", simplifyVector = FALSE)
    labels     <- list()
    sec_titles <- list()
    extraer_pregs <- function(lista) {
      for (p in lista) {
        if (!is.null(p$id) && !is.null(p$texto))
          labels[[p$id]] <<- p$texto
        if (!is.null(p$sub_preguntas)) extraer_pregs(p$sub_preguntas)
        if (!is.null(p$preguntas))     extraer_pregs(p$preguntas)
      }
    }
    for (sec in s$cuestionario$secciones) {
      sec_titles[[sec$id_seccion]] <- sec$titulo
      extraer_pregs(sec$preguntas)
    }
    list(labels = labels, secciones = sec_titles)
  }, error = function(e) list(labels = list(), secciones = list()))
}

ENCUESTA   <- cargar_encuesta_json()
Q_LABELS   <- ENCUESTA$labels
SEC_TITLES <- ENCUESTA$secciones


# =================== HELPERS DE COLUMNAS ===================

# Columnas con datos personales — no se grafican
PRIVATE_COLS <- c("1.2", "1.3", "1.4", "2.1", "2.2", "2.3", "2.4")

# Devuelve TRUE para IDs de pregunta como "1.1", "3.2", "5.3_tabla", "7.4_7.4.1"
is_question_col <- function(name) {
  grepl("^[0-9]+\\.", name)
}

# Extrae el número de sección del ID de pregunta
get_section_num <- function(col_id) {
  as.integer(sub("\\..*", "", col_id))
}

# Agrupa columnas de preguntas por sección (excluye datos personales)
get_section_groups <- function(col_names) {
  qcols    <- col_names[vapply(col_names, is_question_col, logical(1))]
  qcols    <- qcols[!(qcols %in% PRIVATE_COLS)]          # ocultar datos personales
  sec_nums <- unique(suppressWarnings(vapply(qcols, get_section_num, integer(1))))
  sec_nums <- sort(sec_nums[!is.na(sec_nums)])
  result   <- list()
  for (s in sec_nums) {
    result[[as.character(s)]] <- qcols[vapply(qcols, function(x) isTRUE(get_section_num(x) == s), logical(1))]
  }
  result
}

# Etiqueta legible: usa survey.json cuando existe, si no muestra el ID entre corchetes
get_label <- function(col_id) {
  lbl <- Q_LABELS[[col_id]]
  if (!is.null(lbl)) lbl else paste0("[", col_id, "]")
}

# Título de sección desde survey.json o fallback genérico
get_sec_title <- function(sec_num) {
  t <- SEC_TITLES[[as.character(sec_num)]]
  if (!is.null(t)) t else paste("Sección", sec_num)
}

# =================== CARGA DE DATOS ===================

cargar_respuestas_encuestas <- function() {
  tryCatch({
    df <- cargar_desde_firebase()
    if (is.null(df) || nrow(df) == 0) {
      message("Firebase: sin documentos.")
      return(NULL)
    }
    df <- homogenizar_df(df)
    attr(df, "fuente") <- "firebase"
    message("Firebase: ", nrow(df), " documentos cargados.")
    df
  }, error = function(e) {
    message("Firebase error: ", e$message)
    NULL
  })
}

cargar_localidades <- function() {
  tryCatch(
    read_csv("geopoint.csv", show_col_types = FALSE),
    error = function(e) data.frame(Localidad = character(0), Latitud = numeric(0), Longitud = numeric(0))
  )
}

# =================== VISUALIZACIÓN DE PREGUNTAS ===================

plotly_vacio <- function(msg = "Sin datos") {
  plot_ly(type = "scatter", mode = "text", x = 0, y = 0, text = msg,
          textfont = list(size = 14, color = UABCS_COLORS$gris)) %>%
    layout(xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
           margin = list(l = 5, r = 5, t = 5, b = 5),
           paper_bgcolor = PLOTLY_BG, plot_bgcolor = PLOTLY_BG)
}

viz_question <- function(df, col_id) {
  if (!(col_id %in% names(df))) return(plotly_vacio("Columna no encontrada"))
  if (col_id == "4.7.4") return(viz_tabla_especies(df))
  serie <- na.omit(as.character(df[[col_id]]))
  if (length(serie) == 0) return(plotly_vacio())

  conteo        <- as.data.frame(table(serie), stringsAsFactors = FALSE)
  names(conteo) <- c("Opcion", "n")
  conteo        <- conteo[order(conteo$n, decreasing = TRUE), ]
  n_uniq       <- nrow(conteo)
  BG           <- PLOTLY_BG
  BG_PLOT      <- "rgba(255,255,255,0.06)"
  PAL          <- c(UABCS_COLORS$azul, UABCS_COLORS$amarillo, UABCS_COLORS$azul_marino,
                    "#40B9E3", "#7DCFEE", "#003B6E", "#E6B800", "#BAEAF8")

  num   <- suppressWarnings(as.numeric(serie))
  valid <- na.omit(num)
  es_num <- length(valid) >= 0.6 * length(serie) && n_uniq > 6

  if (es_num) {
    # ── Histograma con relleno UABCS ─────────────────────────────────────
    plot_ly(x = valid, type = "histogram", nbinsx = min(20, n_uniq),
            marker = list(color = "rgba(0,159,212,0.82)",
                          line  = list(color = "rgba(255,255,255,0.75)", width = 0.8))) %>%
      layout(xaxis = list(title = "", gridcolor = "rgba(0,0,0,0.07)"),
             yaxis = list(title = "", gridcolor = "rgba(0,0,0,0.07)"),
             showlegend = FALSE, margin = list(l = 5, r = 5, t = 5, b = 30),
             paper_bgcolor = BG, plot_bgcolor = BG_PLOT)

  } else if (n_uniq <= 2) {
    # ── Donut impactante para preguntas binarias (Sí/No, etc.) ───────────
    total <- sum(conteo$n)
    pct   <- round(100 * conteo$n[1] / total, 1)
    plot_ly(conteo, labels = ~Opcion, values = ~n, type = "pie", hole = 0.62,
            textposition = "outside", textinfo = "label+percent",
            marker = list(colors = c(UABCS_COLORS$azul, UABCS_COLORS$amarillo),
                          line   = list(color = "rgba(255,255,255,0.9)", width = 3)),
            hovertemplate = "<b>%{label}</b><br>%{value} personas (%{percent})<extra></extra>") %>%
      layout(showlegend = FALSE,
             annotations = list(list(
               text      = paste0("<b>", pct, "%</b>"),
               x = 0.5, y = 0.5,
               font      = list(size = 22, color = UABCS_COLORS$azul_marino),
               showarrow = FALSE)),
             margin = list(l = 10, r = 10, t = 20, b = 20),
             paper_bgcolor = BG, plot_bgcolor = BG)

  } else if (n_uniq <= 6) {
    # ── Donut artístico con total en el centro ────────────────────────────
    total <- sum(conteo$n)
    plot_ly(conteo, labels = ~Opcion, values = ~n, type = "pie", hole = 0.48,
            textposition = "outside", textinfo = "label+percent",
            outsidetextfont = list(size = 10),
            marker = list(colors = PAL[seq_len(nrow(conteo))],
                          line   = list(color = "rgba(255,255,255,0.75)", width = 2)),
            hovertemplate = "<b>%{label}</b><br>%{value} (%{percent})<extra></extra>") %>%
      layout(showlegend = FALSE,
             annotations = list(list(
               text      = paste0("<b>", total, "</b><br><sup>total</sup>"),
               x = 0.5, y = 0.5,
               font      = list(size = 15, color = UABCS_COLORS$azul_marino),
               showarrow = FALSE)),
             margin = list(l = 10, r = 10, t = 25, b = 25),
             paper_bgcolor = BG, plot_bgcolor = BG)

  } else if (n_uniq <= 14) {
    # ── Lollipop chart para categorías medianas ───────────────────────────
    top_n      <- head(conteo[order(conteo$n), ], 14)
    top_n$ypos <- seq_len(nrow(top_n))
    plot_ly() %>%
      add_segments(
        x = rep(0, nrow(top_n)), xend = top_n$n,
        y = top_n$ypos,          yend = top_n$ypos,
        line       = list(color = "rgba(0,159,212,0.32)", width = 2.5),
        showlegend = FALSE, hoverinfo = "skip"
      ) %>%
      add_trace(
        type = "scatter", mode = "markers",
        x = top_n$n, y = top_n$ypos,
        marker    = list(size = 14, color = top_n$n,
                         colorscale = list(c(0, "#7DCFEE"), c(1, UABCS_COLORS$azul_marino)),
                         showscale  = FALSE,
                         line       = list(color = UABCS_COLORS$amarillo, width = 2.5)),
        text      = paste0(top_n$Opcion, ": ", top_n$n),
        hovertemplate = "%{text}<extra></extra>",
        showlegend = FALSE
      ) %>%
      layout(
        yaxis = list(tickmode = "array", tickvals = top_n$ypos, ticktext = top_n$Opcion,
                     title = "", tickfont = list(size = 10)),
        xaxis = list(title = "", gridcolor = "rgba(0,0,0,0.08)"),
        margin = list(l = 5, r = 20, t = 5, b = 10),
        paper_bgcolor = BG, plot_bgcolor = BG_PLOT)

  } else {
    # ── Treemap para respuestas muy diversas (top 20) ─────────────────────
    top20        <- head(conteo, 20)
    top20$parent <- ""
    plot_ly(top20, type = "treemap",
            labels  = ~Opcion, values = ~n, parents = ~parent,
            textinfo = "label+value+percent root",
            textfont = list(size = 11),
            marker = list(
              colors     = ~n,
              colorscale = list(c(0, UABCS_COLORS$azul_suave),
                                c(0.5, UABCS_COLORS$azul),
                                c(1, UABCS_COLORS$azul_marino)),
              line       = list(color = "rgba(255,255,255,0.85)", width = 2)),
            hovertemplate = "<b>%{label}</b><br>%{value} resp. · %{percentRoot:.1%}<extra></extra>") %>%
      layout(margin      = list(l = 0, r = 0, t = 0, b = 0),
             paper_bgcolor = BG, plot_bgcolor = BG)
  }
}

# ── Visualización especial: tabla Especie × Mes (pregunta 4.7.4) ─────────────
MESES_ORD <- c("Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic")

viz_tabla_especies <- function(df) {
  col_vals <- na.omit(df[["4.7.4"]])
  if (length(col_vals) == 0) return(plotly_vacio("Sin datos de especie por mes"))

  # Agregar todas las respuestas: especie → meses únicos capturados
  acum <- list()
  for (v in col_vals) {
    tryCatch({
      parsed <- jsonlite::fromJSON(v, simplifyVector = TRUE)
      for (sp in names(parsed)) {
        meses <- as.character(unlist(parsed[[sp]]))
        meses <- meses[meses %in% MESES_ORD]
        if (length(meses) == 0) next
        acum[[sp]] <- unique(c(acum[[sp]], meses))
      }
    }, error = function(e) NULL)
  }
  if (length(acum) == 0) return(plotly_vacio("Sin datos de especie por mes"))

  especies <- sort(names(acum))
  mat <- matrix(0L, nrow = length(especies), ncol = length(MESES_ORD),
                dimnames = list(especies, MESES_ORD))
  for (sp in especies)
    for (m in acum[[sp]])
      mat[sp, m] <- 1L

  BG <- PLOTLY_BG
  plot_ly(
    z         = mat,
    x         = MESES_ORD,
    y         = rownames(mat),
    type      = "heatmap",
    colorscale = list(c(0, "#E3F4FB"), c(1, UABCS_COLORS$azul_marino)),
    showscale  = FALSE,
    hovertemplate = "<b>%{y}</b> — %{x}<extra></extra>"
  ) %>%
    layout(
      xaxis  = list(title = "", tickfont = list(size = 10), side = "top"),
      yaxis  = list(title = "", tickfont = list(size = 10), autorange = "reversed"),
      margin = list(l = 5, r = 5, t = 30, b = 5),
      paper_bgcolor = BG, plot_bgcolor = BG
    )
}

# =================== UI ===================

ui <- dashboardPage(
  skin = "blue",
  dashboardHeader(
    title = tagList(
      tags$img(
        src   = "logo_uabcs.png",
        height = "42px",
        style  = "vertical-align:middle; margin-right:8px;"
      ),
      tags$span(
        "Dashboard Pesquero",
        style = "vertical-align:middle; font-size:14px; font-weight:700;"
      )
    ),
    titleWidth = 255
  ),
  dashboardSidebar(width = 255, uiOutput("sidebar_content")),
  dashboardBody(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "style.css")
    ),
    uiOutput("main_tabs_ui")
  )
)

# =================== SERVER ===================

server <- function(input, output, session) {

  autenticado   <- reactiveVal(FALSE)
  usuario_email <- reactiveVal("")

  datos_fuente  <- reactiveVal("cargando")
  cargando_fb   <- reactiveVal(FALSE)
  error_fb      <- reactiveVal(NULL)

  # Almacén central de datos (NULL = no cargado aún)
  .df_data      <- reactiveVal(NULL)

  cargar_fb <- function() {
    cargando_fb(TRUE)
    error_fb(NULL)
    tryCatch({
      df <- cargar_respuestas_encuestas()
      if (is.null(df)) {
        error_fb("No se pudieron obtener datos de Firebase.")
        datos_fuente("error")
        .df_data(NULL)
      } else {
        if ("1.1" %in% names(df)) {
          geo <- cargar_localidades()
          if (nrow(geo) > 0 && "Localidad" %in% names(geo) && "Municipio" %in% names(geo)) {
            mapa_mun     <- setNames(geo$Municipio, geo$Localidad)
            df$Municipio <- mapa_mun[df[["1.1"]]]
          }
        }
        datos_fuente("firebase")
        .df_data(df)
      }
    }, error = function(e) {
      error_fb(paste("Error al conectar con Firebase:", e$message))
      datos_fuente("error")
      .df_data(NULL)
    })
    cargando_fb(FALSE)
  }

  # Carga inicial al autenticarse
  observeEvent(autenticado(), {
    if (isTRUE(autenticado())) cargar_fb()
  })

  # Recarga manual con botón
  observeEvent(input$btn_actualizar, {
    cargar_fb()
  })

  df_respuestas <- reactive({
    req(!is.null(.df_data()))
    .df_data()
  })

  # ── Sidebar dinámico ────────────────────────────────────────────────────
  output$sidebar_content <- renderUI({
    if (!autenticado()) {
      return(tags$div(
        style = "padding: 20px 15px; color: #666; font-size: 13px;",
        tags$em("Inicia sesión para acceder al dashboard.")
      ))
    }

    fuente <- datos_fuente()

    usuario_ui <- tags$div(
      style = "padding: 10px 15px 5px;",
      tags$span(
        style = sprintf("color:%s; font-size:12px;", UABCS_COLORS$gris),
        tags$strong("👤 "), usuario_email()
      ),
      tags$br(),
      actionButton("btn_logout", "Cerrar sesión",
                   class = "btn-default btn-xs",
                   style = "margin-top:4px; width:100%;"),
      tags$br(),
      actionButton("btn_actualizar", "\U0001f504 Actualizar datos",
                   class = "btn-primary btn-sm",
                   style = "margin-top:6px; width:100%;")
    )

    # Estado de carga o error antes de mostrar filtros
    if (isTRUE(cargando_fb())) {
      return(tagList(
        usuario_ui,
        tags$div(style = "padding:15px; color:#666; font-size:13px; text-align:center;",
                 tags$em("Cargando datos de Firebase..."))
      ))
    }

    err <- error_fb()
    if (!is.null(err)) {
      return(tagList(
        usuario_ui,
        tags$div(
          style = "margin:10px; padding:10px; background:#FDECEC; border-radius:6px;
                   border-left:4px solid #CC1E1E; font-size:12px; color:#CC1E1E;",
          tags$strong("\u26a0 Error: "), err
        )
      ))
    }

    df <- df_respuestas()

    filtros <- tagList(
      usuario_ui,
      tags$hr(style = sprintf("border:1px solid %s; margin: 6px 0;", UABCS_COLORS$amarillo)),
      h4("🔍 Filtros", style = sprintf("color:%s; padding:10px;", UABCS_COLORS$azul))
    )

    if ("Municipio" %in% names(df)) {
      muns    <- sort(unique(na.omit(df$Municipio)))
      filtros <- tagList(filtros,
        selectInput("filtro_municipio", "Municipio:",
                    choices = c("Todos", muns), selected = "Todos"))
    }

    if ("1.1" %in% names(df)) {
      locs    <- sort(unique(na.omit(df[["1.1"]])))
      filtros <- tagList(filtros,
        selectInput("filtro_localidad", "Localidad:",
                    choices = c("Todas", locs), selected = "Todas"))
    }

    if ("3.2" %in% names(df)) {
      edades  <- sort(unique(na.omit(df[["3.2"]])))
      filtros <- tagList(filtros,
        selectInput("filtro_edad", "Rango de Edad:",
                    choices = c("Todos", edades), selected = "Todos"))
    }

    color_f <- if (fuente == "firebase") "#2ecc71" else "#e67e22"
    label_f <- if (fuente == "firebase") "\u25cf Firebase en vivo" else "\u25cf Sin conexi\u00f3n"

    tagList(
      filtros,
      tags$hr(style = sprintf("border:1px solid %s;", UABCS_COLORS$amarillo)),
      div(style = "padding:10px 15px;",
          strong("Total: "), textOutput("total_n", inline = TRUE), br(),
          em(style = "font-size:12px;color:#666;", "Filtradas: "),
          textOutput("filtradas_n", inline = TRUE)),
      div(style = "padding:5px 15px 10px;",
          span(style = sprintf("color:%s;font-size:11px;", color_f), label_f))
    )
  })

  output$total_n    <- renderText(nrow(df_respuestas()))
  output$filtradas_n <- renderText(nrow(df_filtrado()))

  # ── Filtrado ────────────────────────────────────────────────────────────
  df_filtrado <- reactive({
    df <- df_respuestas()
    if (!is.null(input$filtro_municipio) && input$filtro_municipio != "Todos" &&
        "Municipio" %in% names(df))
      df <- df[!is.na(df$Municipio) & df$Municipio == input$filtro_municipio, ]
    if (!is.null(input$filtro_localidad) && input$filtro_localidad != "Todas" &&
        "1.1" %in% names(df))
      df <- df[!is.na(df[["1.1"]]) & df[["1.1"]] == input$filtro_localidad, ]
    if (!is.null(input$filtro_edad) && input$filtro_edad != "Todos" &&
        "3.2" %in% names(df))
      df <- df[!is.na(df[["3.2"]]) & df[["3.2"]] == input$filtro_edad, ]
    df
  })

  # ── Cascade: actualiza localidades al cambiar municipio ─────────────────
  observeEvent(input$filtro_municipio, {
    df <- df_respuestas()
    if (!("1.1" %in% names(df))) return()
    locs <- if (!is.null(input$filtro_municipio) && input$filtro_municipio != "Todos" &&
                 "Municipio" %in% names(df)) {
      sort(unique(na.omit(df[["1.1"]][df$Municipio == input$filtro_municipio])))
    } else {
      sort(unique(na.omit(df[["1.1"]])))
    }
    updateSelectInput(session, "filtro_localidad", choices = c("Todas", locs), selected = "Todas")
  }, ignoreInit = TRUE)

  # ── Tabs principales (dinámicos por sección) ────────────────────────────
  output$main_tabs_ui <- renderUI({
    if (!autenticado()) {
      return(tags$div(
        style = "max-width:420px; margin:60px auto; padding:36px 32px; background:#fff;
                 border-radius:12px; border-top:6px solid #009FD4;
                 box-shadow:0 4px 24px rgba(0,0,0,0.10);",
        tags$div(
          style = "text-align:center; margin-bottom:20px;",
          tags$img(src = "logo_uabcs.png", height = "80px", style = "margin-bottom:12px;"),
          tags$h3("Dashboard de Encuestas Pesqueras",
                  style = "color:#00497E; margin:0; font-size:1.3rem;"),
          tags$p("Universidad Autónoma de Baja California Sur",
                 style = "color:#4A5568; font-size:13px; margin:4px 0 0;")
        ),
        tags$hr(style = "border:2px solid #FFD100; margin-bottom:20px;"),
        textInput("login_email", "Correo electrónico", placeholder = "usuario@uabcs.mx",
                  width = "100%"),
        passwordInput("login_password", "Contraseña", placeholder = "••••••••",
                      width = "100%"),
        uiOutput("login_mensaje"),
        actionButton("btn_login", "Iniciar sesión",
                     class = "btn-primary",
                     style = "width:100%; margin-top:8px; font-size:15px;")
      ))
    }

    df     <- df_respuestas()
    groups <- get_section_groups(names(df))

    # Tab Resumen
    resumen_tab <- tabPanel("📊 Resumen",
      fluidRow(
        valueBoxOutput("box_total",   width = 3),
        valueBoxOutput("box_muns",    width = 2),
        valueBoxOutput("box_locs",    width = 3),
        valueBoxOutput("box_complet", width = 2),
        valueBoxOutput("box_campos",  width = 2)
      ),
      fluidRow(
        column(4, h4("Respuestas por Municipio"), plotlyOutput("plot_municipio", height = "280px")),
        column(4, h4("Respuestas por Localidad"), plotlyOutput("plot_localidad", height = "280px")),
        column(4, h4("Distribución por Edad (preg. 3.2)"), plotlyOutput("plot_edad", height = "280px"))
      )
    )

    # Un tab por sección: dos preguntas por fila
    sec_tabs <- lapply(names(groups), function(sec) {
      cols <- groups[[sec]]
      n    <- length(cols)
      rows <- vector("list", ceiling(n / 2))
      for (i in seq(1, n, by = 2)) {
        c1   <- cols[[i]]
        c2   <- if (i + 1 <= n) cols[[i + 1]] else NULL
        oid1 <- paste0("sq_", sec, "_", i)
        oid2 <- if (!is.null(c2)) paste0("sq_", sec, "_", i + 1) else NULL
        col2_ui <- if (!is.null(c2)) {
          column(6,
            div(style = sprintf("color:%s;font-weight:600;font-size:13px;padding:6px 0 2px;",
                                UABCS_COLORS$azul_marino), get_label(c2)),
            plotlyOutput(oid2, height = "260px")
          )
        } else NULL
        rows[[ceiling(i / 2)]] <- fluidRow(
          column(6,
            div(style = sprintf("color:%s;font-weight:600;font-size:13px;padding:6px 0 2px;",
                                UABCS_COLORS$azul_marino), get_label(c1)),
            plotlyOutput(oid1, height = "260px")
          ),
          col2_ui
        )
      }
      tabPanel(paste0("📋 ", get_sec_title(sec)), do.call(tagList, rows))
    })

    # Tab Análisis cruzado
    all_q <- unlist(groups, use.names = FALSE)
    analisis_tab <- if (length(all_q) >= 2) {
      q_choices <- setNames(all_q, vapply(all_q, get_label, character(1)))
      tabPanel("📈 Análisis",
        fluidRow(
          column(6, selectInput("var1", "Variable 1:", choices = q_choices,
                                selected = all_q[[1]])),
          column(6, selectInput("var2", "Variable 2:", choices = q_choices,
                                selected = all_q[[min(2, length(all_q))]]))
        ),
        plotlyOutput("plot_cruce", height = "450px")
      )
    } else NULL

    # Tab Datos crudos
    datos_tab <- tabPanel("📊 Datos",
      downloadButton("descargar_csv", "\u2b07 Descargar CSV"), br(), br(),
      DTOutput("tabla_datos")
    )

    all_panels <- c(
      list(resumen_tab),
      sec_tabs,
      if (!is.null(analisis_tab)) list(analisis_tab) else list(),
      list(datos_tab)
    )
    do.call(tabBox, c(list(id = "main_tabs", width = 12), all_panels))
  })

  # ── Value boxes ─────────────────────────────────────────────────────────
  output$box_total   <- renderValueBox(
    valueBox(nrow(df_filtrado()), "Encuestas", icon("chart-bar"), color = "blue"))
  output$box_muns    <- renderValueBox({
    df <- df_filtrado()
    n  <- if ("Municipio" %in% names(df)) dplyr::n_distinct(df$Municipio, na.rm = TRUE) else "\u2013"
    valueBox(sprintf("%s/5", n), "Municipios", icon("map"), color = "blue")
  })
  output$box_locs    <- renderValueBox({
    df <- df_filtrado()
    n  <- if ("1.1" %in% names(df)) dplyr::n_distinct(df[["1.1"]], na.rm = TRUE) else "\u2013"
    valueBox(sprintf("%s/18", n), "Localidades", icon("map-marker"), color = "blue")
  })
  output$box_complet <- renderValueBox({
    df  <- df_filtrado()
    pct <- if (nrow(df) > 0) round(100 * sum(!is.na(df)) / (nrow(df) * ncol(df)), 1) else 0
    valueBox(sprintf("%.1f%%", pct), "Completitud", icon("check"), color = "green")
  })
  output$box_campos  <- renderValueBox(
    valueBox(ncol(df_filtrado()), "Campos", icon("database"), color = "yellow"))

  # ── Gráficas de resumen ─────────────────────────────────────────────────
  output$plot_municipio <- renderPlotly({
    df <- df_filtrado()
    if (!("Municipio" %in% names(df))) return(plotly_vacio("Sin datos de Municipio"))
    muns <- df %>% dplyr::count(Municipio) %>% dplyr::rename(Nom = 1) %>% dplyr::arrange(n)
    muns$ypos <- seq_len(nrow(muns))
    plot_ly() %>%
      add_segments(
        x = rep(0, nrow(muns)), xend = muns$n,
        y = muns$ypos, yend = muns$ypos,
        line = list(color = "rgba(0,73,126,0.28)", width = 2.5),
        showlegend = FALSE, hoverinfo = "skip"
      ) %>%
      add_trace(
        type = "scatter", mode = "markers",
        x = muns$n, y = muns$ypos,
        marker = list(size = 13, color = muns$n,
                      colorscale = list(c(0, UABCS_COLORS$azul_suave),
                                        c(1, UABCS_COLORS$azul_marino)),
                      showscale = FALSE,
                      line = list(color = UABCS_COLORS$amarillo, width = 2)),
        text      = paste0(muns$Nom, ": ", muns$n),
        hovertemplate = "%{text} encuestas<extra></extra>",
        showlegend = FALSE
      ) %>%
      layout(
        yaxis = list(tickmode = "array", tickvals = muns$ypos, ticktext = muns$Nom,
                     title = "", tickfont = list(size = 9)),
        xaxis = list(title = "", gridcolor = "rgba(0,0,0,0.08)"),
        showlegend = FALSE, margin = list(l = 5, r = 20, t = 5, b = 5),
        paper_bgcolor = PLOTLY_BG, plot_bgcolor = "rgba(255,255,255,0.06)")
  })

  output$plot_localidad <- renderPlotly({
    df <- df_filtrado()
    if (!("1.1" %in% names(df))) return(plotly_vacio("Sin datos de Localidad"))
    locs <- df %>% dplyr::count(.data[["1.1"]]) %>% dplyr::rename(Localidad = 1) %>%
              dplyr::arrange(n) %>% tail(15)
    locs$ypos <- seq_len(nrow(locs))
    plot_ly() %>%
      add_segments(
        x = rep(0, nrow(locs)), xend = locs$n,
        y = locs$ypos, yend = locs$ypos,
        line = list(color = "rgba(0,73,126,0.28)", width = 2.5),
        showlegend = FALSE, hoverinfo = "skip"
      ) %>%
      add_trace(
        type = "scatter", mode = "markers",
        x = locs$n, y = locs$ypos,
        marker = list(size = 13, color = locs$n,
                      colorscale = list(c(0, UABCS_COLORS$azul_suave),
                                        c(1, UABCS_COLORS$azul_marino)),
                      showscale = FALSE,
                      line = list(color = UABCS_COLORS$amarillo, width = 2)),
        text      = paste0(locs$Localidad, ": ", locs$n),
        hovertemplate = "%{text} encuestas<extra></extra>",
        showlegend = FALSE
      ) %>%
      layout(
        yaxis = list(tickmode = "array", tickvals = locs$ypos, ticktext = locs$Localidad,
                     title = "", tickfont = list(size = 9)),
        xaxis = list(title = "", gridcolor = "rgba(0,0,0,0.08)"),
        showlegend = FALSE, margin = list(l = 5, r = 20, t = 5, b = 5),
        paper_bgcolor = PLOTLY_BG, plot_bgcolor = "rgba(255,255,255,0.06)")
  })

  output$plot_edad <- renderPlotly({
    df <- df_filtrado()
    if (!("3.2" %in% names(df))) return(plotly_vacio("Sin columna 3.2 (edad)"))
    conteo <- df %>% dplyr::count(.data[["3.2"]]) %>% dplyr::rename(Edad = 1)
    total  <- sum(conteo$n)
    plot_ly(conteo, labels = ~Edad, values = ~n, type = "pie", hole = 0.48,
            textposition = "inside", textinfo = "label+percent",
            marker = list(colors = c(UABCS_COLORS$azul, UABCS_COLORS$azul_marino,
                                     UABCS_COLORS$amarillo, "#40B9E3", "#E6B800",
                                     UABCS_COLORS$gris),
                          line = list(color = "rgba(255,255,255,0.8)", width = 2)),
            hovertemplate = "<b>%{label}</b><br>%{value} (%{percent})<extra></extra>") %>%
      layout(showlegend = TRUE,
             annotations = list(list(
               text = paste0("<b>", total, "</b><br><sup>total</sup>"),
               x = 0.5, y = 0.5,
               font = list(size = 13, color = UABCS_COLORS$azul_marino),
               showarrow = FALSE)),
             margin = list(l = 5, r = 5, t = 5, b = 5),
             paper_bgcolor = PLOTLY_BG, plot_bgcolor = PLOTLY_BG)
  })

  # ── Gráficas dinámicas de cada pregunta ─────────────────────────────────
  # Registra los renderPlotly una sola vez cuando cambia la estructura de datos
  observe({
    df     <- df_respuestas()
    groups <- get_section_groups(names(df))
    for (sec in names(groups)) {
      local({
        sec_  <- sec
        cols_ <- groups[[sec_]]
        for (i in seq_along(cols_)) {
          local({
            col_id_ <- cols_[[i]]
            oid_    <- paste0("sq_", sec_, "_", i)
            output[[oid_]] <- renderPlotly(viz_question(df_filtrado(), col_id_))
          })
        }
      })
    }
  })

  # ── Análisis cruzado ────────────────────────────────────────────────────
  output$plot_cruce <- renderPlotly({
    req(input$var1, input$var2)
    req(input$var1 != input$var2)
    df <- df_filtrado()
    req(input$var1 %in% names(df), input$var2 %in% names(df))
    sub_df <- na.omit(df[, c(input$var1, input$var2), drop = FALSE])
    req(nrow(sub_df) > 0)
    tbl <- table(as.character(sub_df[[1]]), as.character(sub_df[[2]]))
    req(nrow(tbl) > 0, ncol(tbl) > 0)
    plot_ly(z = tbl, x = colnames(tbl), y = rownames(tbl), type = "heatmap",
            colorscale = list(c(0, UABCS_COLORS$azul_suave),
                              c(0.5, UABCS_COLORS$azul),
                              c(1, UABCS_COLORS$azul_marino)),
            text = tbl,
            texttemplate = "%{text}", textfont = list(size = 10)) %>%
      layout(xaxis = list(title = get_label(input$var2)),
             yaxis = list(title = get_label(input$var1)),
             margin = list(l = 120, r = 20, t = 20, b = 120),
             paper_bgcolor = PLOTLY_BG, plot_bgcolor = PLOTLY_BG)
  })

  # ── Datos crudos ────────────────────────────────────────────────────────
  output$tabla_datos <- renderDT(
    df_filtrado(), options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)

  output$descargar_csv <- downloadHandler(
    filename = function() sprintf("encuestas_%s.csv", Sys.Date()),
    content  = function(file) write_csv(df_filtrado(), file)
  )

  # ── Autenticación: login ────────────────────────────────────────────────
  login_error <- reactiveVal(NULL)

  output$login_mensaje <- renderUI({
    msg <- login_error()
    if (!is.null(msg)) {
      tags$div(
        style = "color:#CC1E1E; background:#FDECEC; border-radius:6px;
                 padding:8px 12px; margin-bottom:8px; font-size:13px;",
        tags$strong("⚠ "), msg
      )
    }
  })

  observeEvent(input$btn_login, {
    email    <- trimws(input$login_email)
    password <- input$login_password
    if (nchar(email) == 0 || nchar(password) == 0) {
      login_error("Por favor ingresa tu correo y contraseña.")
      return()
    }
    login_error(NULL)
    resultado <- autenticar_usuario(email, password)
    if (isTRUE(resultado$ok)) {
      autenticado(TRUE)
      usuario_email(resultado$email)
    } else {
      login_error(resultado$error)
    }
  })

  # ── Autenticación: logout ───────────────────────────────────────────────
  observeEvent(input$btn_logout, {
    autenticado(FALSE)
    usuario_email("")
  })
}

shinyApp(ui, server)
