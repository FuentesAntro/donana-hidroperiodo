# 07_sentinel2_busqueda.R
# Busca escenas Sentinel-2 L2A sobre Donana en Microsoft Planetary Computer.
# Solo catalogo: no descarga imagenes.

for (p in c("rstac", "dplyr", "ggplot2")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("Falta el paquete ", p, ": install.packages('", p, "')")
}
library(rstac)
library(dplyr)
library(ggplot2)

bbox   <- c(-6.798880, 36.783859, -6.161775, 37.339267)  # lon/lat, WGS84
inicio <- "2022-01-01"
fin    <- "2026-11-09"

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "|", ..., "\n")

log_msg("Consultando catalogo Planetary Computer ...")
busqueda <- stac("https://planetarycomputer.microsoft.com/api/stac/v1") |>
  stac_search(
    collections = "sentinel-2-l2a",
    bbox        = bbox,
    datetime    = paste0(inicio, "T00:00:00Z/", fin, "T23:59:59Z"),
    limit       = 200
  ) |>
  post_request()

items <- items_fetch(busqueda)   # recorre todas las paginas
n <- length(items$features)
log_msg("Escenas encontradas:", n)
if (n == 0) stop("No se encontro ninguna escena. Revisa bbox y fechas.")

# Tabla de escenas
campo <- function(f, nombre, tipo = NA_character_) {
  v <- f$properties[[nombre]]
  if (is.null(v)) tipo else v
}
catalogo <- tibble(
  id         = vapply(items$features, function(f) f$id, character(1)),
  fecha_hora = vapply(items$features, function(f) campo(f, "datetime"), character(1)),
  tesela     = vapply(items$features, function(f) campo(f, "s2:mgrs_tile"), character(1)),
  nubes_pct  = vapply(items$features, function(f) campo(f, "eo:cloud_cover", NA_real_), numeric(1)),
  sin_dato_pct = vapply(items$features,
                        function(f) campo(f, "s2:nodata_pixel_percentage", NA_real_), numeric(1))
) |>
  mutate(fecha = as.Date(substr(fecha_hora, 1, 10))) |>
  arrange(fecha, tesela)

# Resumen
cat("\n--- Resumen ---\n")
cat("Rango de fechas:", format(min(catalogo$fecha)), "->", format(max(catalogo$fecha)), "\n")
cat("\nEscenas por tesela:\n")
print(count(catalogo, tesela))
cat("\nEscenas con nubes < 20 %:", sum(catalogo$nubes_pct < 20, na.rm = TRUE), "\n")
cat("Escenas con nubes < 50 %:", sum(catalogo$nubes_pct < 50, na.rm = TRUE), "\n")
cat("\nEscenas por anio (todas / nubes < 20 %):\n")
print(catalogo |>
        mutate(anio = format(fecha, "%Y")) |>
        group_by(anio) |>
        summarise(todas = n(), claras = sum(nubes_pct < 20, na.rm = TRUE)))

# Guardado
dir.create("data/raw/sentinel2_catalogo", showWarnings = FALSE, recursive = TRUE)
ruta <- file.path("data/raw/sentinel2_catalogo",
                  paste0("sentinel2_l2a_escenas_", Sys.Date(), ".csv"))
write.csv(catalogo, ruta, row.names = FALSE)
log_msg("Catalogo guardado:", ruta)

# Grafico de nubosidad en el tiempo
dir.create("figures", showWarnings = FALSE)
g <- ggplot(catalogo, aes(fecha, nubes_pct, colour = tesela)) +
  geom_point(alpha = 0.5) +
  theme_minimal() +
  labs(title = "Sentinel-2 L2A sobre Donana: nubosidad por escena",
       x = NULL, y = "Nubes (%)", colour = "Tesela",
       caption = "Fuente: Microsoft Planetary Computer (catalogo STAC)")
ggsave("figures/sentinel2_nubosidad.png", g, width = 8, height = 4.5, dpi = 200)
print(g)
