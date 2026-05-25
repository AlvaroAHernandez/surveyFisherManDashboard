library(httr); library(openssl); library(jsonlite); library(dplyr)

CRED_PATH           <- "surver-fisherman-uabcs-firebase-adminsdk-fbsvc-5c73dae273.json"
FIREBASE_COLLECTION <- "survey_responses"
.fb_env             <- new.env(parent = emptyenv())

base64url_encode <- function(x) {
  if (is.character(x)) x <- charToRaw(x)
  b64 <- gsub("[[:space:]]", "", openssl::base64_encode(x))
  sub("=+$", "", chartr("+/", "-_", b64))
}
obtener_token_firebase <- function() {
  cred    <- jsonlite::fromJSON(CRED_PATH)
  header  <- base64url_encode('{"alg":"RS256","typ":"JWT"}')
  now     <- as.integer(Sys.time())
  payload <- base64url_encode(jsonlite::toJSON(list(
    iss=cred$client_email,sub=cred$client_email,
    aud="https://oauth2.googleapis.com/token",
    iat=now,exp=now+3600L,scope="https://www.googleapis.com/auth/datastore"
  ),auto_unbox=TRUE))
  si  <- paste0(header,".",payload)
  key <- openssl::read_key(gsub("\\\\n","\n",cred$private_key))
  sig <- openssl::signature_create(charToRaw(si),hash=openssl::sha256,key=key)
  jwt <- paste0(si,".",base64url_encode(sig))
  r   <- httr::POST("https://oauth2.googleapis.com/token",
    body=list(grant_type="urn:ietf:params:oauth:grant-type:jwt-bearer",assertion=jwt),encode="form")
  httr::content(r)$access_token
}
parse_firestore_value <- function(v) {
  if (!is.null(v$stringValue))  return(v$stringValue)
  if (!is.null(v$integerValue)) return(v$integerValue)
  if (!is.null(v$doubleValue))  return(v$doubleValue)
  if (!is.null(v$booleanValue)) return(v$booleanValue)
  if (!is.null(v$timestampValue)) return(v$timestampValue)
  if (!is.null(v$mapValue))     return(lapply(v$mapValue$fields, parse_firestore_value))
  if (!is.null(v$arrayValue))   { vals <- v$arrayValue$values; return(if(is.null(vals)) list() else lapply(vals,parse_firestore_value)) }
  NA
}
parse_firestore_doc <- function(doc) {
  result <- list()
  for (fname in names(doc$fields)) {
    val <- parse_firestore_value(doc$fields[[fname]])
    if (fname=="responses" && is.list(val)) { for(k in names(val)) result[[k]] <- val[[k]] }
    else result[[fname]] <- val
  }
  result
}

token <- obtener_token_firebase()
pid   <- jsonlite::fromJSON(CRED_PATH)$project_id
url   <- sprintf("https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s",pid,FIREBASE_COLLECTION)
resp  <- httr::GET(url, httr::add_headers(Authorization=paste("Bearer",token)))
data  <- httr::content(resp, as="parsed")
docs  <- data$documents

rows  <- lapply(docs, parse_firestore_doc)
df    <- dplyr::bind_rows(lapply(rows, function(r) {
  r[vapply(r,is.list,logical(1))] <- NA
  r <- lapply(r, function(v) if(length(v)==1) as.character(v) else NA_character_)
  as.data.frame(r, stringsAsFactors=FALSE, check.names=FALSE)
}))

cat("=== DIMENSIONES ===\n")
cat("Filas:", nrow(df), " Columnas:", ncol(df), "\n\n")

q_cols <- names(df)[vapply(names(df), function(x) grepl("^[0-9]+\\.", x), logical(1))]
cat("=== VALORES POR PREGUNTA (2-20 únicos) ===\n")
for (col in q_cols) {
  vals <- na.omit(as.character(df[[col]]))
  uniq <- sort(unique(vals))
  if (length(uniq) >= 2 && length(uniq) <= 20) {
    cat(sprintf("[%s] (%d únicos):\n", col, length(uniq)))
    for (v in uniq) cat(sprintf("  - \"%s\"\n", v))
  }
}

cat("\n=== PREGUNTAS CON MUCHOS VALORES (texto libre) ===\n")
for (col in q_cols) {
  vals <- na.omit(as.character(df[[col]]))
  uniq <- unique(vals)
  if (length(uniq) > 20) {
    cat(sprintf("[%s] %d únicos - top 10:\n", col, length(uniq)))
    top <- head(sort(table(vals), decreasing=TRUE), 10)
    for (nm in names(top)) cat(sprintf("  %d x \"%s\"\n", top[[nm]], nm))
  }
}
