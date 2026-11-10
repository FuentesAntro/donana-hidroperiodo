# =============================================================================
# scripts/04_api_hidromet.R
# Descarga por API de Hidromet (ICTS-RBD / EBD-CSIC): nivel de agua diario
#
# API: https://datos-automaticos.icts-donana.es/api/v1/  (abierta, sin clave)
# Límite: 100 peticiones/hora en los endpoints de datos (aquí usamos 1 o 2).
# Licencia de los datos: CC BY 4.0. Citar la fuente e indicar la fecha de consulta.
#
# Qué hace:
#   1. Pide la serie diaria completa (recorre las páginas si hay más de una).
#   2. Guarda la respuesta ORIGINAL (JSON) en data/raw/hidromet_api/ sin tocarla.
#   3. Crea un CSV con el mismo formato que el del portal (cabecera # + Date,Value).
#   4. Registra fecha, URL, tamaño y hash en data/raw/DESCARGAS_LOG.csv
#   5. Compara con el CSV descargado a mano y muestra las diferencias.
#
# Uso:  source("scripts/04_api_hidromet.R")
# =============================================================================

paquetes <- c("httr2", "jsonlite", "dplyr", "readr", "fs", "digest", "glue")
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  stop("Faltan paquetes: ", paste(faltan, collapse = ", "),
       "\nInstálalos con renv::install(c(",
       paste0('"', faltan, '"', collapse = ", "), ")) y luego renv::snapshot()",
       call. = FALSE)
}
invisible(lapply(paquetes, library, character.only = TRUE))

# ----------------------------------------------------------------------------
# 1. CONFIGURACIÓN
# ----------------------------------------------------------------------------
BASE           <- "https://datos-automaticos.icts-donana.es"
UA             <- "DonanaWatch (proyecto academico)"
DIR_API        <- "data/raw/hidromet_api"
LOG_PATH       <- "data/raw/DESCARGAS_LOG.csv"
MANUAL         <- "data/raw/hidromet/cancela_millan_waterLevel_diario.csv"
FECHA_DESCARGA <- Sys.Date()

# Cancela Millán = estación 8437 (según /api/v1/catalog/stations/)
q <- list(
  place    = 8437,
  nombre   = "cancela_millan",
  variable = "waterLevel",
  acronym  = "WaterLevelMestech",
  calc     = "Average",
  aggr     = "Average",
  desde    = "2022-01-01",
  hasta    = as.character(Sys.Date() - 1)   # el portal da datos hasta ayer
)

dir_create(DIR_API)
msg <- function(...) message(format(Sys.time(), "%H:%M:%S"), " | ", ...)

# ----------------------------------------------------------------------------
# 2. FUNCIONES
# ----------------------------------------------------------------------------
pedir_pagina <- function(q, pagina) {
  request(BASE) |>
    req_url_path("/api/v1/daily/") |>
    req_url_query(place = q$place, variable = q$variable, acronym = q$acronym,
                  calc_procedure_method = q$calc, aggr_method = q$aggr,
                  start_date = q$desde, end_date = q$hasta,
                  page = pagina, page_size = 5000) |>
    req_user_agent(UA) |>
    req_retry(max_tries = 3) |>
    req_perform()
}

registrar_log <- function(archivo, url) {
  fila <- tibble::tibble(
    fuente         = "Hidromet (API)",
    archivo        = as.character(archivo),
    url            = url,
    fecha_descarga = as.character(FECHA_DESCARGA),
    bytes          = as.numeric(file_size(archivo)),
    sha256         = digest(file = archivo, algo = "sha256"),
    licencia       = "CC BY 4.0"
  )
  existe <- file_exists(LOG_PATH)
  write_csv(fila, LOG_PATH, append = existe, col_names = !existe)
}

# ----------------------------------------------------------------------------
# 3. DESCARGA (todas las páginas)
# ----------------------------------------------------------------------------
prefijo <- glue("hidromet_{q$nombre}_{q$variable}_daily_{FECHA_DESCARGA}")
paginas <- list()
pagina  <- 1

repeat {
  msg("Pidiendo página ", pagina, " ...")
  resp <- pedir_pagina(q, pagina)
  txt  <- resp_body_string(resp)

  json_path <- path(DIR_API, glue("{prefijo}_p{pagina}.json"))
  write_lines(txt, json_path)                 # respuesta original, sin tocar
  registrar_log(json_path, resp$url)

  paginas[[pagina]] <- fromJSON(txt, simplifyVector = TRUE)
  if (is.null(paginas[[pagina]]$pagination$`next`)) break
  pagina <- pagina + 1
  Sys.sleep(1)
}

meta <- paginas[[1]]$metadata
res  <- bind_rows(lapply(paginas, function(p) as.data.frame(p$results)))
msg("Recibidas ", nrow(res), " filas. Campos: ", paste(names(res), collapse = ", "))

if (!"date" %in% names(res)) {
  stop("La respuesta no tiene campo 'date'. Campos: ", paste(names(res), collapse = ", "))
}
col_valor <- if ("value" %in% names(res)) "value" else {
  num <- names(res)[vapply(res, is.numeric, logical(1))]
  if (length(num) == 0) stop("No encuentro columna numérica con el valor.")
  num[1]
}
msg("Columna de valor: ", col_valor)

# ----------------------------------------------------------------------------
# 4. CSV EN EL MISMO FORMATO QUE EL DEL PORTAL
# ----------------------------------------------------------------------------
out <- tibble::tibble(
  Date  = as.character(as.Date(substr(res$date, 1, 10))),
  Value = as.numeric(res[[col_valor]])
) |>
  distinct(Date, .keep_all = TRUE) |>
  arrange(Date)

cabecera <- c(
  "# ============================================================",
  "# DATASET: Hidromet API - Donana National Park (ICTS-RBD / EBD-CSIC)",
  paste0("# ", names(meta), ": ", vapply(meta, function(x) paste(x, collapse = " "), character(1))),
  paste0("# API place (station_id): ", q$place),
  paste0("# Download date (API): ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "# ============================================================"
)
csv_path <- path(DIR_API, glue("{prefijo}.csv"))
write_lines(cabecera, csv_path)
write_csv(out, csv_path, append = TRUE, col_names = TRUE)
registrar_log(csv_path, paste0(BASE, "/api/v1/daily/ (convertido a CSV)"))
msg("CSV guardado: ", csv_path, " (", nrow(out), " filas, ",
    min(out$Date), " -> ", max(out$Date), ")")

# ----------------------------------------------------------------------------
# 5. COMPARACIÓN CON EL CSV DESCARGADO A MANO
# ----------------------------------------------------------------------------
if (file_exists(MANUAL)) {
  man <- read_csv(MANUAL, comment = "#", show_col_types = FALSE) |>
    transmute(Date = as.character(as.Date(Date)), Value_manual = as.numeric(Value))
  cmp <- full_join(out, man, by = "Date")
  solapan <- cmp |> filter(!is.na(Value), !is.na(Value_manual))
  dif     <- abs(solapan$Value - solapan$Value_manual)

  cat("\n--- Comparación API vs CSV manual ---\n")
  cat("Días en ambos:          ", nrow(solapan), "\n")
  cat("Solo en la API:         ", sum(is.na(cmp$Value_manual) & !is.na(cmp$Value)), "\n")
  cat("Solo en el CSV manual:  ", sum(is.na(cmp$Value) & !is.na(cmp$Value_manual)), "\n")
  cat("Días con valor distinto (>1e-6): ", sum(dif > 1e-6), "\n")
  cat("Diferencia máxima (m):  ", signif(max(dif, 0), 3), "\n")
  nuevos <- cmp |> filter(!is.na(Value), is.na(Value_manual)) |> pull(Date)
  if (length(nuevos) > 0) cat("Fechas nuevas de la API: ", paste(head(nuevos, 5), collapse = ", "),
                              if (length(nuevos) > 5) " ..." else "", "\n")
} else {
  msg("No encuentro el CSV manual para comparar: ", MANUAL)
}

cat("\nFecha de descarga para docs/fuentes_de_datos.md: ",
    format(FECHA_DESCARGA), " (API)\n", sep = "")
