# =============================================================================
# scripts/03_lluvia_y_nivel.R
# Une la lluvia diaria de Meteo Palacio con el nivel de agua de Hidromet
#
# Entradas : data/raw/meteo_palacio/palacio_precipitacion_diaria.csv  (NO se modifica)
#            data/processed/hidromet_cancela_millan_nivel_diario.csv  (salida del 02)
# Salidas  : data/processed/palacio_lluvia_ano_hidro.csv
#            data/processed/lluvia_nivel_diario.csv
#            figures/lluvia_y_nivel.png
#
# Datos: ICTS-RBD / EBD-CSIC (Meteo Palacio e Hidromet). Licencia CC BY 4.0.
# Año hidrológico = octubre a septiembre, etiquetado por el año en que termina.
# =============================================================================

library(readr)
library(dplyr)
library(fs)
library(lubridate)

# ----------------------------------------------------------------------------
# 1. CONFIGURACIÓN
# ----------------------------------------------------------------------------
RAW_PALACIO <- "data/raw/meteo_palacio/palacio_precipitacion_diaria.csv"
PROC_HIDRO  <- "data/processed/hidromet_cancela_millan_nivel_diario.csv"
OUT_ANUAL   <- "data/processed/palacio_lluvia_ano_hidro.csv"
OUT_DIARIO  <- "data/processed/lluvia_nivel_diario.csv"
OUT_FIG     <- "figures/lluvia_y_nivel.png"

# Un año hidrológico se considera "completo" con al menos este nº de días con dato
MIN_DIAS_CON_DATO <- 355

stopifnot(file_exists(RAW_PALACIO), file_exists(PROC_HIDRO))
dir_create(c("data/processed", "figures"))

# ----------------------------------------------------------------------------
# 2. LECTURA
# ----------------------------------------------------------------------------
meta_p <- readLines(RAW_PALACIO, warn = FALSE, encoding = "UTF-8")
meta_p <- meta_p[startsWith(meta_p, "#")]
fecha_desc_p <- trimws(sub("^#\\s*download_ts:\\s*", "",
                           meta_p[grepl("download_ts", meta_p)][1]))

p <- read_csv(RAW_PALACIO, comment = "#",
              col_types = cols(Date = col_date(), Value = col_double())) |>
  transmute(fecha = Date, lluvia_mm = Value) |>
  arrange(fecha)

if (anyDuplicated(p$fecha) > 0) stop("Fechas repetidas en el CSV de lluvia.")
if (any(p$lluvia_mm < 0, na.rm = TRUE)) warning("Hay lluvias negativas: revísalas.")
message("Lluvia: ", nrow(p), " días, ", min(p$fecha), " -> ", max(p$fecha),
        " | sin dato: ", sum(is.na(p$lluvia_mm)))

h <- read_csv(PROC_HIDRO, comment = "#", show_col_types = FALSE) |>
  mutate(fecha = as.Date(fecha))

# ----------------------------------------------------------------------------
# 3. LLUVIA POR AÑO HIDROLÓGICO Y COMPARACIÓN CON LA MEDIA HISTÓRICA
# ----------------------------------------------------------------------------
anual <- p |>
  mutate(ano_hidro = if_else(month(fecha) >= 10, year(fecha) + 1L, year(fecha))) |>
  group_by(ano_hidro) |>
  summarise(
    dias          = n(),
    dias_con_dato = sum(!is.na(lluvia_mm)),
    lluvia_mm     = round(sum(lluvia_mm, na.rm = TRUE), 1),
    .groups = "drop"
  ) |>
  mutate(completo = dias >= 365 & dias_con_dato >= MIN_DIAS_CON_DATO)

media_ref <- mean(anual$lluvia_mm[anual$completo])
n_ref     <- sum(anual$completo)

anual <- anual |>
  mutate(
    media_historica_mm = round(media_ref, 1),
    anomalia_pct = if_else(completo, round(100 * (lluvia_mm / media_ref - 1), 1), NA_real_)
  )

cat("\nLluvia por año hidrológico (oct-sep), últimos 10:\n")
print(tail(anual, 10), width = Inf)
cat("\nMedia de ", n_ref, " años completos: ", round(media_ref, 1), " mm\n", sep = "")
cat("Un año con pocos días (p. ej. el que está en curso) no se compara: anomalia_pct = NA.\n")

cab_anual <- c(
  "# Serie derivada de datos de ICTS-RBD / EBD-CSIC (Meteo Palacio). Licencia CC BY 4.0.",
  "# Fuente: https://meteorologia-palacio.icts-donana.es/",
  "# Estación: Palacio - Lodos Estación Manual. Variable: precipitación diaria (mm).",
  paste0("# Fecha de descarga del dato original: ", fecha_desc_p),
  paste0("# Procesado el: ", Sys.Date(), " con scripts/03_lluvia_y_nivel.R"),
  paste0("# Año completo = al menos ", MIN_DIAS_CON_DATO, " días con dato. ",
         "media_historica_mm = media de los años completos (", n_ref, ")."),
  "# Los años sin completar no tienen anomalía calculada."
)
write_lines(cab_anual, OUT_ANUAL)
write_csv(anual, OUT_ANUAL, append = TRUE, col_names = TRUE)

# ----------------------------------------------------------------------------
# 4. UNIÓN DIARIA LLUVIA + NIVEL (solo el periodo con nivel)
# ----------------------------------------------------------------------------
j <- h |>
  left_join(p, by = "fecha") |>
  select(fecha, ano_hidro, lluvia_mm, nivel_m, nivel_limpio_m, estado)

cab_diario <- c(
  "# Unión de Hidromet (nivel de agua, Cancela Millán) y Meteo Palacio (lluvia). CC BY 4.0.",
  "# Fuentes: https://datos-automaticos.icts-donana.es/ y https://meteorologia-palacio.icts-donana.es/",
  "# ICTS-RBD / EBD-CSIC. Los datos no se han alterado; 'estado' marca la calidad del nivel.",
  paste0("# Procesado el: ", Sys.Date(), " con scripts/03_lluvia_y_nivel.R"),
  "# Atención: son dos estaciones distintas, no están en el mismo punto."
)
write_lines(cab_diario, OUT_DIARIO)
write_csv(j, OUT_DIARIO, append = TRUE, col_names = TRUE)
message("Guardado: ", OUT_DIARIO, " (", nrow(j), " filas)")

# ----------------------------------------------------------------------------
# 5. GRÁFICO: lluvia diaria arriba, nivel de agua abajo
# ----------------------------------------------------------------------------
png(OUT_FIG, width = 1600, height = 1000, res = 160)
par(mfrow = c(2, 1), mar = c(2, 5, 3, 1), oma = c(2, 0, 0, 0))

plot(j$fecha, j$lluvia_mm, type = "h", col = "steelblue",
     xlab = "", ylab = "Lluvia diaria (mm)",
     main = "Lluvia (Palacio) y nivel de agua (Cancela Millán)")

plot(j$fecha, j$nivel_limpio_m, type = "l", lwd = 1.2,
     xlab = "", ylab = "Nivel de agua (m)")
legend("topleft", bty = "n", legend = "Solo días válidos (sin huecos ni dudosos)")

mtext(paste("Fuente: ICTS-RBD / EBD-CSIC (Meteo Palacio, Hidromet), CC BY 4.0.",
            "Lluvia descargada:", fecha_desc_p),
      side = 1, outer = TRUE, line = 0.5, cex = 0.7)
dev.off()
message("Figura guardada: ", OUT_FIG)
