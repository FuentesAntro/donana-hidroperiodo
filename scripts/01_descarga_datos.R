# =============================================================================
# scripts/01_descarga_datos.R
# Descarga y registro de datos brutos de ICTS-Doñana (Hidromet y Meteo Palacio)
#
# Qué hace:
#   1. Descarga por API (si está configurada) o registra CSV bajados a mano.
#   2. Nunca sobrescribe: cada descarga lleva la fecha en el nombre.
#   3. Anota procedencia (URL, fecha, hash, licencia) en data/raw/DESCARGAS_LOG.csv
#   4. Valida lo descargado (filas, rango de fechas, % de NA).
#   5. Imprime la fecha de descarga para pegarla en docs/fuentes_de_datos.md
#
# Licencia de los datos: CC BY 4.0. Condiciones: citar fuente, no alterar el
# sentido de la información e indicar la fecha de consulta (por eso el log).
#
# Uso:  source("scripts/01_descarga_datos.R")
# =============================================================================

paquetes <- c("httr2", "readr", "dplyr", "fs", "digest", "glue", "lubridate")
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  stop("Faltan paquetes: ", paste(faltan, collapse = ", "),
       "\nInstálalos con renv::install(c(",
       paste0('"', faltan, '"', collapse = ", "), ")) y luego renv::snapshot()",
       call. = FALSE)
}
invisible(lapply(paquetes, library, character.only = TRUE))

# ----------------------------------------------------------------------------
# 1. CONFIGURACIÓN  <-- AQUÍ SE RELLENA LO QUE SALE EN LA PESTAÑA "API"
# ----------------------------------------------------------------------------
FECHA_DESCARGA <- Sys.Date()
DIR_RAW        <- "data/raw"
LOG_PATH       <- path(DIR_RAW, "DESCARGAS_LOG.csv")

# Rango de años a pedir (Hidromet empieza en 2020; Meteo Palacio en 1978)
ANIO_FIN <- year(FECHA_DESCARGA)

fuentes <- list(
  hidromet = list(
    nombre   = "Hidromet",
    modo     = "manual",              # cambia a "api" cuando tengas los datos
    url_base = NA_character_,         # p. ej. la dirección base que muestra la pestaña API
    ruta     = NA_character_,         # p. ej. el endpoint concreto
    params   = list(),                # parámetros fijos (estación, variable, agregación...)
    param_desde = NA_character_,      # nombre del parámetro de fecha inicial
    param_hasta = NA_character_,      # nombre del parámetro de fecha final
    formato_fecha = "%Y-%m-%d",       # formato que pida la API
    extension = "csv",
    anio_ini = 2020,
    licencia = "CC BY 4.0",
    cita = "ICTS-RBD / EBD-CSIC (2026). Datos hidrometeorologicos de la red de monitorizacion de la Reserva Biologica de Donana. Hidromet. https://hidromet.icts-donana.es/"
  ),
  meteo_palacio = list(
    nombre   = "Meteo Palacio",
    modo     = "manual",
    url_base = NA_character_,
    ruta     = NA_character_,
    params   = list(),
    param_desde = NA_character_,
    param_hasta = NA_character_,
    formato_fecha = "%Y-%m-%d",
    extension = "csv",
    anio_ini = 1978,
    licencia = "CC BY 4.0",
    cita = "ICTS-RBD / EBD-CSIC (2026). Datos meteorologicos de la Estacion Manual del Palacio de Donana. Meteo Palacio. https://meteopalacio.icts-donana.es/"
  )
)

# Token o cabecera de autenticación, si la API lo pidiera (déjalo NULL si no)
API_HEADERS <- NULL   # p. ej. list(Authorization = "Bearer xxx"). No lo subas al repo.

# ----------------------------------------------------------------------------
# 2. FUNCIONES AUXILIARES
# ----------------------------------------------------------------------------
msg <- function(...) message(format(Sys.time(), "%H:%M:%S"), " | ", ...)

registrar_log <- function(fuente, archivo, url, licencia) {
  fila <- tibble::tibble(
    fuente         = fuente,
    archivo        = as.character(archivo),
    url            = url,
    fecha_descarga = as.character(FECHA_DESCARGA),
    bytes          = as.numeric(file_size(archivo)),
    sha256         = digest(file = archivo, algo = "sha256"),
    licencia       = licencia
  )
  existe <- file_exists(LOG_PATH)
  write_csv(fila, LOG_PATH, append = existe, col_names = !existe)
  invisible(fila)
}

# Trocea un rango en años naturales (evita peticiones enormes con datos cada 5 min)
trocear_anios <- function(anio_ini, anio_fin) {
  tibble::tibble(
    anio  = anio_ini:anio_fin,
    desde = as.Date(paste0(anio_ini:anio_fin, "-01-01")),
    hasta = pmin(as.Date(paste0(anio_ini:anio_fin, "-12-31")), FECHA_DESCARGA)
  )
}

# Una petición con reintentos, espera entre peticiones y cabecera identificable
pedir <- function(url, params, headers = NULL) {
  req <- request(url) |>
    req_user_agent("DonanaWatch (proyecto academico; contacto: ver README)") |>
    req_url_query(!!!params) |>
    req_retry(max_tries = 4, backoff = ~ 5 * 2^(.x - 1)) |>
    req_throttle(rate = 30 / 60) |>      # máx. 30 peticiones por minuto
    req_timeout(300)
  if (!is.null(headers)) req <- req_headers(req, !!!headers)
  req_perform(req)
}

# Descarga por API: un archivo por año, sin sobrescribir
descargar_api <- function(id, f) {
  falta <- c("url_base", "ruta", "param_desde", "param_hasta")
  if (any(vapply(f[falta], function(x) length(x) == 0 || is.na(x), logical(1)))) {
    stop("Fuente '", id, "': rellena url_base, ruta, param_desde y param_hasta ",
         "en la configuración con lo que muestra la pestaña API.", call. = FALSE)
  }
  dir_destino <- dir_create(path(DIR_RAW, id))
  url <- paste0(sub("/+$", "", f$url_base), "/", sub("^/+", "", f$ruta))
  tramos <- trocear_anios(f$anio_ini, ANIO_FIN)

  for (i in seq_len(nrow(tramos))) {
    t <- tramos[i, ]
    destino <- path(dir_destino,
                    glue("{id}_{t$anio}_descargado_{FECHA_DESCARGA}.{f$extension}"))
    if (file_exists(destino)) { msg("Ya existe, salto: ", path_file(destino)); next }

    params <- f$params
    params[[f$param_desde]] <- format(t$desde, f$formato_fecha)
    params[[f$param_hasta]] <- format(t$hasta, f$formato_fecha)

    msg(f$nombre, " ", t$anio, " ...")
    resp <- tryCatch(pedir(url, params, API_HEADERS), error = function(e) {
      msg("  ERROR ", t$anio, ": ", conditionMessage(e)); NULL
    })
    if (is.null(resp)) next
    if (length(resp_body_raw(resp)) < 50) { msg("  Respuesta vacía, no se guarda."); next }

    writeBin(resp_body_raw(resp), destino)
    registrar_log(f$nombre, destino, resp$url, f$licencia)
    msg("  OK -> ", path_file(destino))
  }
}

# Modo manual: registra los CSV que hayas bajado a mano a data/raw/<id>/
registrar_manual <- function(id, f) {
  dir_destino <- dir_create(path(DIR_RAW, id))
  archivos <- dir_ls(dir_destino, regexp = "\\.(csv|txt)$")
  if (length(archivos) == 0) {
    msg("Fuente '", id, "' en modo manual: no hay archivos. Descarga el CSV desde el ",
        "portal y guárdalo en ", dir_destino)
    return(invisible(NULL))
  }
  log_prev <- if (file_exists(LOG_PATH)) read_csv(LOG_PATH, show_col_types = FALSE) else NULL
  for (a in archivos) {
    ya <- !is.null(log_prev) && digest(file = a, algo = "sha256") %in% log_prev$sha256
    if (ya) next
    registrar_log(f$nombre, a, "descarga manual desde el portal", f$licencia)
    msg("Registrado: ", path_file(a))
  }
}

# Validación básica de un CSV: filas, rango de fechas y NA
validar_csv <- function(archivo) {
  # Los CSV de ICTS-Doñana traen un bloque de metadatos con líneas que empiezan
  # por "#". Se ignoran al leer (el archivo original NO se modifica).
  lineas <- readLines(archivo, n = 200, warn = FALSE, encoding = "UTF-8")
  datos  <- lineas[!startsWith(lineas, "#") & nzchar(lineas)]
  cabecera <- if (length(datos) > 0) datos[1] else ""
  delim <- if (lengths(regmatches(cabecera, gregexpr(";", cabecera))) >
               lengths(regmatches(cabecera, gregexpr(",", cabecera)))) ";" else ","

  d <- suppressWarnings(read_delim(archivo, delim = delim, comment = "#",
                                   show_col_types = FALSE, guess_max = 10000))

  # Busca la columna de fecha: por tipo o por nombre, y la convierte si es texto
  es_fecha <- vapply(d, inherits, logical(1), c("POSIXct", "Date"))
  col_fecha <- names(d)[es_fecha][1]
  if (is.na(col_fecha)) {
    cand <- names(d)[grepl("date|fecha|time|day|dia", names(d), ignore.case = TRUE)]
    if (length(cand) > 0) {
      parseada <- suppressWarnings(parse_date_time(
        as.character(d[[cand[1]]]),
        orders = c("Ymd HMS", "Ymd HM", "Ymd", "dmY HMS", "dmY HM", "dmY"),
        quiet = TRUE))
      if (mean(!is.na(parseada)) > 0.9) { d[[cand[1]]] <- parseada; col_fecha <- cand[1] }
    }
  }
  rango <- if (!is.na(col_fecha)) {
    paste(format(min(d[[col_fecha]], na.rm = TRUE)), "->",
          format(max(d[[col_fecha]], na.rm = TRUE)))
  } else "sin columna de fecha detectada"
  tibble::tibble(
    archivo = path_file(archivo),
    filas   = nrow(d),
    columnas = ncol(d),
    rango_fechas = rango,
    pct_NA  = round(100 * mean(is.na(d)), 1)
  )
}

# ----------------------------------------------------------------------------
# 3. EJECUCIÓN
# ----------------------------------------------------------------------------
dir_create(DIR_RAW)

for (id in names(fuentes)) {
  f <- fuentes[[id]]
  msg("=== ", f$nombre, " (modo: ", f$modo, ") ===")
  if (f$modo == "api") descargar_api(id, f) else registrar_manual(id, f)
}

# Validación de todo lo que haya en data/raw
csvs <- dir_ls(DIR_RAW, recurse = TRUE, regexp = "\\.csv$")
csvs <- csvs[!path_file(csvs) %in% c("DESCARGAS_LOG.csv", "VALIDACION.csv")]
if (length(csvs) > 0) {
  msg("Validando ", length(csvs), " archivo(s)...")
  informe <- dplyr::bind_rows(lapply(csvs, validar_csv))
  print(informe, n = Inf, width = Inf)
  write_csv(informe, path(DIR_RAW, "VALIDACION.csv"))
  if (any(informe$filas == 0)) warning("Hay archivos con 0 filas: revísalos.")
}

cat("\n----------------------------------------------------------\n")
cat("Fecha de descarga para docs/fuentes_de_datos.md: ",
    format(FECHA_DESCARGA), "\n", sep = "")
cat("Sustituye '(pendiente)' por esa fecha en las filas de Hidromet y Meteo Palacio\n")
cat("y en las citas (las condiciones de uso exigen indicar la fecha de consulta).\n")
cat("----------------------------------------------------------\n")
