# =============================================================================
# scripts/05_api_meteo_palacio.R
# Descarga por API de Meteo Palacio (ICTS-RBD / EBD-CSIC): precipitación diaria
#
# API: https://meteorologia-palacio.icts-donana.es/api/  (abierta, sin clave)
# Límite: 100 peticiones/hora en los endpoints de datos (aquí unas 5).
# Licencia de los datos: CC BY 4.0. Citar la fuente e indicar la fecha de consulta.
#
# Qué hace:
#   1. Pide la serie diaria de lluvia (P_RAIN) por tramos de 10 años
#      (la API ignora 'page' y corta a 5000 filas por petición).
#   2. Guarda la respuesta ORIGINAL (JSON) en data/raw/meteo_palacio_api/ sin tocarla.
#   3. Crea un CSV (cabecera # + Date,Value).
#   4. Registra fecha, URL, tamaño y hash en data/raw/DESCARGAS_LOG.csv
#   5. Compara con el CSV descargado a mano (si lo encuentra) y muestra diferencias.
#
# Uso:  source("scripts/05_api_meteo_palacio.R")
# =============================================================================

paquetes <- c("httr2", "jsonlite", "dplyr", "readr", "fs", "digest", "glue", "tibble")
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
BASE           <- "https://meteorologia-palacio.icts-donana.es"
UA             <- "DonanaWatch (proyecto academico)"
DIR_API        <- "data/raw/meteo_palacio_api"
LOG_PATH       <- "data/raw/DESCARGAS_LOG.csv"
FECHA_DESCARGA <- Sys.Date()
TRAMO_ANIOS    <- 10                      # años por petición (tope API: 5000 filas)

q <- list(
  variable = "P_RAIN",                    # código eLTER (equivale a Prec)
  nombre   = "palacio",
  desde    = "1978-09-01",
  hasta    = as.character(Sys.Date() - 1)
)

dir_create(DIR_API)
msg <- function(...) message(format(Sys.time(), "%H:%M:%S"), " | ", ...)

# ----------------------------------------------------------------------------
# 2. FUNCIONES
# ----------------------------------------------------------------------------
# La API ignora el parámetro 'page' y limita cada petición a max_rows (5000),
# así que se pide por tramos de fechas (10 años = ~3650 días < 5000).
pedir_tramo <- function(q, desde, hasta) {
  request(BASE) |>
    req_url_path("/api/daily/") |>
    req_url_query(variable = q$variable, start_date = desde, end_date = hasta) |>
    req_user_agent(UA) |>
    req_retry(max_tries = 3) |>
    req_perform()
}

registrar_log <- function(archivo, url) {
  fila <- tibble::tibble(
    fuente         = "Meteo Palacio (API)",
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

# Extrae del JSON de una página las filas de la variable pedida
extraer_filas <- function(p) {
  bloques <- Filter(function(b) identical(b$elter_code, q$variable) ||
                      identical(b$variable, "Prec"), p$variable_blocks)
  if (length(bloques) == 0) return(NULL)
  bind_rows(lapply(bloques, function(b) {
    tibble::tibble(
      station = b$station,
      date    = vapply(b$data, function(x) as.character(x$date), ""),
      value   = vapply(b$data, function(x)
        if (is.null(x$value)) NA_character_ else as.character(x$value), "")
    )
  }))
}

# ----------------------------------------------------------------------------
# 3. DESCARGA (por tramos de fechas)
# ----------------------------------------------------------------------------
prefijo <- glue("meteo_{q$nombre}_{q$variable}_daily_{FECHA_DESCARGA}")
filas   <- list()
fair    <- NULL
recortado <- FALSE

inicios <- seq(as.Date(q$desde), as.Date(q$hasta), by = paste(TRAMO_ANIOS, "years"))
finales <- pmin(c(inicios[-1] - 1, as.Date(q$hasta)), as.Date(q$hasta))

for (i in seq_along(inicios)) {
  desde_i <- as.character(inicios[i])
  hasta_i <- as.character(finales[i])
  msg("Tramo ", i, "/", length(inicios), ": ", desde_i, " -> ", hasta_i)

  resp <- pedir_tramo(q, desde_i, hasta_i)
  txt  <- resp_body_string(resp)

  json_path <- path(DIR_API, glue("{prefijo}_t{i}.json"))
  write_lines(txt, json_path)                  # respuesta original, sin tocar
  registrar_log(json_path, resp$url)

  p <- fromJSON(txt, simplifyVector = FALSE)
  if (i == 1) fair <- p$fair
  msg("  count = ", p$count, " | returned = ", p$returned, " | max_rows = ", p$max_rows)

  # Si el tramo llega al tope de la API, puede faltar parte: lo avisamos
  if (!is.null(p$count) && !is.null(p$max_rows) &&
      as.numeric(p$count) > as.numeric(p$max_rows)) {
    recortado <- TRUE
    warning("Tramo ", desde_i, " -> ", hasta_i, ": count (", p$count,
            ") > max_rows (", p$max_rows, "). Reduce TRAMO_ANIOS.")
  }

  f <- extraer_filas(p)
  if (is.null(f) || nrow(f) == 0) { msg("  tramo sin filas"); next }
  msg("  filas: ", nrow(f))
  filas[[length(filas) + 1]] <- f
  Sys.sleep(1)
}

res <- bind_rows(filas)
if (nrow(res) == 0) stop("No se recibió ningún dato de ", q$variable)

estaciones <- unique(res$station)
msg("Estación(es) en la respuesta: ", paste(estaciones, collapse = " | "))
if (length(estaciones) > 1) {
  warning("Hay más de una estación en la respuesta; revisa antes de usar los datos.")
}

out <- tibble::tibble(
  Date  = as.character(as.Date(substr(res$date, 1, 10))),
  Value = suppressWarnings(as.numeric(res$value))
) |>
  distinct(Date, .keep_all = TRUE) |>
  arrange(Date)

if (nrow(out) < nrow(res)) {
  msg("Aviso: ", nrow(res) - nrow(out), " fechas repetidas descartadas (tramos solapados)")
}
msg("Total filas: ", nrow(out), " (la API anunció count = ", p$count, " en el último tramo)",
    if (recortado) " | ATENCIÓN: algún tramo estaba recortado" else "")

# ----------------------------------------------------------------------------
# 4. CSV
# ----------------------------------------------------------------------------
fair_txt <- unlist(fair)
cabecera <- c(
  "# ============================================================",
  "# DATASET: Meteo Palacio API - Donana (ICTS-RBD / EBD-CSIC)",
  if (length(fair_txt) > 0)
    paste0("# ", names(fair_txt), ": ", gsub("[\r\n]+", " ", fair_txt)),
  paste0("# Station: ", paste(estaciones, collapse = " | ")),
  paste0("# Variable: ", q$variable, " (Prec, mm)"),
  paste0("# Download date (API): ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "# ============================================================"
)
csv_path <- path(DIR_API, glue("{prefijo}.csv"))
write_lines(cabecera, csv_path)
write_csv(out, csv_path, append = TRUE, col_names = TRUE)
registrar_log(csv_path, paste0(BASE, "/api/daily/ (convertido a CSV)"))
msg("CSV guardado: ", csv_path, " (", nrow(out), " filas, ",
    min(out$Date), " -> ", max(out$Date), ")")
msg("Días sin dato (NA) en la serie: ", sum(is.na(out$Value)))

# ----------------------------------------------------------------------------
# 5. COMPARACIÓN CON EL CSV DESCARGADO A MANO
# ----------------------------------------------------------------------------
candidatos <- dir_ls("data/raw", recurse = TRUE, regexp = "(?i)palacio.*\\.csv$")
candidatos <- candidatos[!grepl("meteo_palacio_api", candidatos)]

if (length(candidatos) >= 1) {
  MANUAL <- candidatos[1]
  msg("Comparo con: ", MANUAL)
  man <- read_csv(MANUAL, comment = "#", show_col_types = FALSE)
  col_f <- if ("Date" %in% names(man)) "Date" else names(man)[1]
  col_v <- if ("Value" %in% names(man)) "Value" else names(man)[2]
  man <- tibble::tibble(
    Date         = as.character(as.Date(man[[col_f]])),
    Value_manual = suppressWarnings(as.numeric(man[[col_v]]))
  )
  cmp <- full_join(out, man, by = "Date")
  ambos   <- cmp |> filter(!is.na(Value), !is.na(Value_manual))
  dif     <- abs(ambos$Value - ambos$Value_manual)

  cat("\n--- Comparación API vs CSV manual ---\n")
  cat("Días con valor en ambos:        ", nrow(ambos), "\n")
  cat("Solo en la API:                 ", sum(is.na(cmp$Value_manual) & !is.na(cmp$Value)), "\n")
  cat("Solo en el CSV manual:          ", sum(is.na(cmp$Value) & !is.na(cmp$Value_manual)), "\n")
  cat("Días con valor distinto (>1e-6):", sum(dif > 1e-6), "\n")
  cat("Diferencia máxima (mm):         ", signif(max(dif, 0), 3), "\n")
  nuevos <- cmp |> filter(!is.na(Value), is.na(Value_manual)) |> pull(Date)
  if (length(nuevos) > 0) cat("Fechas nuevas de la API: ", paste(head(nuevos, 5), collapse = ", "),
                              if (length(nuevos) > 5) " ..." else "", "\n")
} else {
  msg("No encuentro el CSV manual de Palacio en data/raw/ para comparar.")
}

cat("\nFecha de descarga para docs/fuentes_de_datos.md: ",
    format(FECHA_DESCARGA), " (API)\n", sep = "")
