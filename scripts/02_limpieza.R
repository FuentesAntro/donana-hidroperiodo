# =============================================================================
# scripts/02_limpieza.R
# Limpieza de la serie diaria de nivel de agua (Hidromet, Cancela Millán)
#
# Entrada : data/raw/hidromet/cancela_millan_waterLevel_diario.csv  (NO se modifica)
# Salida  : data/processed/hidromet_cancela_millan_nivel_diario.csv
#           figures/hidromet_nivel_diario.png
#
# Qué hace:
#   1. Lee el CSV ignorando el bloque de metadatos (líneas que empiezan por "#").
#   2. Construye un calendario completo de días (para ver los huecos).
#   3. Marca cada día: "ok", "hueco" o "dudoso_salto_sensor".
#   4. Guarda la serie con una cabecera de fuente, licencia y fecha de descarga.
#   5. Resume los días válidos por año hidrológico y dibuja la serie.
#
# Datos: ICTS-RBD / EBD-CSIC, Hidromet. Licencia CC BY 4.0.
# Unidad: metros (water_surface_height_above_datum).
# =============================================================================

library(readr)
library(dplyr)
library(fs)
library(lubridate)

# ----------------------------------------------------------------------------
# 1. CONFIGURACIÓN
# ----------------------------------------------------------------------------
ARCHIVO_RAW <- "data/raw/hidromet/cancela_millan_waterLevel_diario.csv"
DIR_OUT     <- "data/processed"
DIR_FIG     <- "figures"
SALIDA_CSV  <- path(DIR_OUT, "hidromet_cancela_millan_nivel_diario.csv")
SALIDA_PNG  <- path(DIR_FIG, "hidromet_nivel_diario.png")

# Primer día del salto brusco (0,03 m -> 13,5 m). Causa pendiente de confirmar
# con la ICTS-Doñana. Desde esta fecha los datos se marcan como dudosos.
FECHA_SALTO <- as.Date("2026-07-04")

stopifnot(file_exists(ARCHIVO_RAW))
dir_create(c(DIR_OUT, DIR_FIG))

# ----------------------------------------------------------------------------
# 2. LECTURA (sin tocar el archivo original)
# ----------------------------------------------------------------------------
lineas <- readLines(ARCHIVO_RAW, warn = FALSE, encoding = "UTF-8")
meta   <- lineas[startsWith(lineas, "#")]

fecha_descarga <- trimws(sub("^#\\s*Download date\\s*:\\s*", "",
                             meta[grepl("Download date", meta)][1]))

d <- read_csv(ARCHIVO_RAW, comment = "#", show_col_types = FALSE) |>
  transmute(fecha = as.Date(Date), nivel_m = as.numeric(Value)) |>
  arrange(fecha)

if (anyDuplicated(d$fecha) > 0) {
  stop("Hay fechas repetidas en el archivo: revísalo antes de seguir.")
}
message("Leídas ", nrow(d), " filas: ", min(d$fecha), " -> ", max(d$fecha))

# ----------------------------------------------------------------------------
# 3. CALENDARIO COMPLETO Y MARCAS DE CALIDAD
# ----------------------------------------------------------------------------
out <- tibble(fecha = seq(min(d$fecha), max(d$fecha), by = "day")) |>
  left_join(d, by = "fecha") |>
  mutate(
    estado = case_when(
      is.na(nivel_m)       ~ "hueco",
      fecha >= FECHA_SALTO ~ "dudoso_salto_sensor",
      TRUE                 ~ "ok"
    ),
    nivel_limpio_m = if_else(estado == "ok", nivel_m, NA_real_),
    # Año hidrológico: octubre a septiembre, etiquetado por el año en que termina
    # (p. ej. 2025 = octubre 2024 - septiembre 2025)
    ano_hidro = if_else(month(fecha) >= 10, year(fecha) + 1L, year(fecha))
  ) |>
  select(fecha, ano_hidro, nivel_m, nivel_limpio_m, estado)

# ----------------------------------------------------------------------------
# 4. GUARDAR CON CABECERA DE PROCEDENCIA
# ----------------------------------------------------------------------------
cabecera <- c(
  "# Serie derivada de datos de ICTS-RBD / EBD-CSIC (Hidromet). Licencia CC BY 4.0.",
  "# Fuente: https://datos-automaticos.icts-donana.es/",
  "# Estación: Cancela Millán. Variable: nivel de agua medio diario (Mestech), en metros.",
  paste0("# Fecha de descarga del dato original: ", fecha_descarga),
  paste0("# Procesado el: ", Sys.Date(), " con scripts/02_limpieza.R"),
  paste0("# Marcas: ok / hueco (sin dato) / dudoso_salto_sensor (desde ", FECHA_SALTO, ")."),
  "# nivel_m = valor original; nivel_limpio_m = solo días 'ok'.",
  "# No se ha alterado el valor de ningún dato, solo se han marcado."
)
write_lines(cabecera, SALIDA_CSV)
write_csv(out, SALIDA_CSV, append = TRUE, col_names = TRUE)
message("Guardado: ", SALIDA_CSV)

# ----------------------------------------------------------------------------
# 5. RESUMEN POR AÑO HIDROLÓGICO
# ----------------------------------------------------------------------------
resumen <- out |>
  group_by(ano_hidro) |>
  summarise(
    dias       = n(),
    ok         = sum(estado == "ok"),
    hueco      = sum(estado == "hueco"),
    dudoso     = sum(estado == "dudoso_salto_sensor"),
    pct_ok     = round(100 * ok / dias, 1),
    nivel_max_ok_m = round(suppressWarnings(max(nivel_limpio_m, na.rm = TRUE)), 3),
    .groups = "drop"
  )
cat("\nResumen por año hidrológico (oct-sep):\n")
print(resumen, n = Inf, width = Inf)

# Bloques consecutivos de huecos (para informar y para el gráfico)
bloques <- function(flag) {
  r   <- rle(flag)
  fin <- cumsum(r$lengths)
  ini <- fin - r$lengths + 1
  idx <- which(r$values)
  tibble(ini = ini[idx], fin = fin[idx])
}
b_hueco <- bloques(out$estado == "hueco")
if (nrow(b_hueco) > 0) {
  cat("\nBloques sin datos:\n")
  print(tibble(desde = out$fecha[b_hueco$ini],
               hasta = out$fecha[b_hueco$fin],
               dias  = b_hueco$fin - b_hueco$ini + 1), n = Inf)
}

# ----------------------------------------------------------------------------
# 6. GRÁFICO (gris = hueco, rojo = dudoso)
# ----------------------------------------------------------------------------
ymax <- max(out$nivel_limpio_m, na.rm = TRUE) * 1.15
ylim <- c(0, ymax)

png(SALIDA_PNG, width = 1600, height = 800, res = 160)
par(mar = c(4, 5, 3, 1))
plot(out$fecha, out$nivel_limpio_m, type = "n", ylim = ylim,
     xlab = "", ylab = "Nivel de agua medio diario (m)",
     main = "Hidromet - Cancela Millán: nivel de agua")

for (k in seq_len(nrow(b_hueco))) {
  rect(out$fecha[b_hueco$ini[k]] - 0.5, ylim[1],
       out$fecha[b_hueco$fin[k]] + 0.5, ylim[2],
       col = adjustcolor("grey60", 0.4), border = NA)
}
b_dud <- bloques(out$estado == "dudoso_salto_sensor")
for (k in seq_len(nrow(b_dud))) {
  rect(out$fecha[b_dud$ini[k]] - 0.5, ylim[1],
       out$fecha[b_dud$fin[k]] + 0.5, ylim[2],
       col = adjustcolor("red", 0.2), border = NA)
}
lines(out$fecha, out$nivel_limpio_m, lwd = 1.2)
legend("topleft", bty = "n", fill = c(adjustcolor("grey60", 0.4), adjustcolor("red", 0.2)),
       border = NA, legend = c("Sin datos", "Dudoso (salto del sensor)"))
mtext(paste("Fuente: ICTS-RBD / EBD-CSIC, Hidromet (CC BY 4.0). Descarga:", fecha_descarga),
      side = 1, line = 2.8, cex = 0.7)
dev.off()
message("Figura guardada: ", SALIDA_PNG)
