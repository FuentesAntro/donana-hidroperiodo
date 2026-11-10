# 09_sentinel2_serie.R
# Serie piloto: una fecha cada 'paso_dias', con la mejor (menos nubes) de cada ventana.
# Guarda estadisticas por figura y un raster de clases por fecha. Se puede reanudar.

for (p in c("rstac", "gdalcubes", "terra", "sf", "dplyr")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("Falta el paquete ", p, ": install.packages('", p, "')")
}
library(rstac); library(gdalcubes); library(terra); library(sf); library(dplyr)

inicio    <- as.Date("2024-10-01")
fin       <- as.Date("2026-07-03")
paso_dias <- 30
n_max     <- Inf      # pon 2 para una primera prueba corta

dir_clases <- "data/processed/sentinel2_clases"
dir_stats  <- "data/processed/sentinel2_serie"
dir.create(dir_clases, showWarnings = FALSE, recursive = TRUE)
dir.create(dir_stats,  showWarnings = FALSE, recursive = TRUE)
csv_stats <- file.path(dir_stats, "estadisticas_por_fecha.csv")

# --- Elegir fechas desde el catalogo (sin duplicados)
cat_csv <- tail(sort(list.files("data/raw/sentinel2_catalogo",
                                pattern = "\\.csv$", full.names = TRUE)), 1)
fechas <- read.csv(cat_csv) |>
  mutate(fecha = as.Date(fecha)) |>
  distinct(fecha, tesela, .keep_all = TRUE) |>
  filter(fecha >= inicio, fecha <= fin) |>
  group_by(fecha) |>
  summarise(teselas = n(), nubes = mean(nubes_pct, na.rm = TRUE), .groups = "drop") |>
  filter(teselas >= 4) |>
  mutate(ventana = floor(as.numeric(fecha - inicio) / paso_dias)) |>
  group_by(ventana) |>
  slice_min(nubes, n = 1, with_ties = FALSE) |>
  ungroup() |>
  pull(fecha)
fechas <- head(fechas, n_max)
cat("Fechas a procesar:", length(fechas), "\n")

# --- Zona y figuras
zona <- st_read("data/processed/zona_estudio_donana.gpkg", quiet = TRUE) |> st_transform(32629)
figs <- st_read("data/processed/donana_figuras.gpkg", quiet = TRUE) |> st_transform(32629)
bb <- st_bbox(zona)
bb4326 <- as.numeric(st_bbox(st_transform(zona, 4326)))
api <- stac("https://planetarycomputer.microsoft.com/api/stac/v1")

procesar <- function(fecha) {
  items <- api |>
    stac_search(collections = "sentinel-2-l2a", bbox = bb4326,
                datetime = paste0(fecha, "T00:00:00Z/", fecha, "T23:59:59Z"), limit = 50) |>
    post_request() |> items_sign(sign_planetary_computer())
  col <- stac_image_collection(items$features, asset_names = c("B03", "B11", "SCL"))
  v <- cube_view(srs = "EPSG:32629",
                 extent = list(t0 = as.character(fecha), t1 = as.character(fecha),
                               left = unname(bb["xmin"]), right = unname(bb["xmax"]),
                               bottom = unname(bb["ymin"]), top = unname(bb["ymax"])),
                 dx = 20, dy = 20, dt = "P1D", aggregation = "first", resampling = "near")
  tmp <- tempfile(); dir.create(tmp)
  f <- write_tif(raster_cube(col, v), dir = tmp, prefix = "s2_")
  r <- rast(f[1]); names(r) <- c("B03", "B11", "SCL")

  off <- if (fecha >= as.Date("2022-01-25")) 1000 else 0
  verde <- (r$B03 - off) / 10000
  swir  <- (r$B11 - off) / 10000
  mndwi <- (verde - swir) / (verde + swir)
  scl <- r$SCL
  valido <- !is.na(scl) & (scl == 2 | (scl >= 4 & scl <= 7))
  clase <- ifel(valido, ifel(mndwi > 0, 2, 1), 0)
  writeRaster(clase, file.path(dir_clases, paste0("clase_", fecha, ".tif")),
              datatype = "INT1U", overwrite = TRUE)

  agua <- clase == 2
  res <- do.call(rbind, lapply(seq_len(nrow(figs)), function(i) {
    dentro <- !is.na(rasterize(vect(figs[i, ]), r))
    n  <- global(dentro, "sum", na.rm = TRUE)[1, 1]
    nv <- global(dentro & valido, "sum", na.rm = TRUE)[1, 1]
    na <- global(dentro & agua, "sum", na.rm = TRUE)[1, 1]
    data.frame(fecha = as.character(fecha), figura = figs$FIGURA[i],
               ha_zona = round(n * 400 / 1e4), pct_valido = round(100 * nv / n, 1),
               ha_agua = round(na * 400 / 1e4), pct_agua = round(100 * na / nv, 1))
  }))
  unlink(tmp, recursive = TRUE)
  res
}

hechas <- if (file.exists(csv_stats)) unique(read.csv(csv_stats)$fecha) else character(0)
for (fe in as.character(fechas)) {
  if (fe %in% hechas) { cat(fe, "ya hecha, la salto\n"); next }
  cat(format(Sys.time(), "%H:%M:%S"), "| Procesando", fe, "...\n")
  res <- tryCatch(procesar(as.Date(fe)),
                  error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
  if (!is.null(res)) {
    write.table(res, csv_stats, sep = ",", row.names = FALSE,
                col.names = !file.exists(csv_stats), append = file.exists(csv_stats))
    pn <- res[res$figura == "Parque Nacional", ]
    cat(sprintf("  PN: %s ha de agua (%.1f %% valido)\n", pn$ha_agua, pn$pct_valido))
  }
}
cat("\nListo. Estadisticas en", csv_stats, "\n")
