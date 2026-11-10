# 08_sentinel2_prueba.R
# Prueba con UNA fecha: lee B03, B11 y SCL, recorta a Donana, enmascara nubes
# y calcula agua con MNDWI. No procesa toda la serie.

for (p in c("rstac", "gdalcubes", "terra", "sf", "dplyr")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("Falta el paquete ", p, ": install.packages('", p, "')")
}
library(rstac); library(gdalcubes); library(terra); library(sf); library(dplyr)

# --- Fecha de prueba: NULL = elige sola la fecha con mas teselas claras (ene-abr 2026)
fecha_prueba <- NULL

cat_csv <- tail(sort(list.files("data/raw/sentinel2_catalogo",
                                pattern = "\\.csv$", full.names = TRUE)), 1)
catalogo <- read.csv(cat_csv) |> mutate(fecha = as.Date(fecha))

if (is.null(fecha_prueba)) {
  fecha_prueba <- catalogo |>
    filter(fecha >= as.Date("2026-01-01"), fecha <= as.Date("2026-04-30"),
           nubes_pct < 20) |>
    group_by(fecha) |>
    summarise(teselas = n(), nubes = mean(nubes_pct), .groups = "drop") |>
    arrange(desc(teselas), nubes) |>
    slice(1) |> pull(fecha)
}
fecha_prueba <- as.Date(fecha_prueba)
cat("Fecha de prueba:", format(fecha_prueba), "\n")

# --- Zona de estudio en UTM 29N
zona <- st_read("data/processed/zona_estudio_donana.gpkg", quiet = TRUE) |>
  st_transform(32629)
bb <- st_bbox(zona)
bb4326 <- as.numeric(st_bbox(st_transform(zona, 4326)))

# --- Buscar escenas de ese dia (URLs firmadas de Planetary Computer)
items <- stac("https://planetarycomputer.microsoft.com/api/stac/v1") |>
  stac_search(collections = "sentinel-2-l2a", bbox = bb4326,
              datetime = paste0(fecha_prueba, "T00:00:00Z/", fecha_prueba, "T23:59:59Z"),
              limit = 50) |>
  post_request() |>
  items_sign(sign_planetary_computer())
cat("Escenas ese dia:", length(items$features), "\n")
cat("Teselas:", paste(vapply(items$features,
                             function(f) f$properties[["s2:mgrs_tile"]], character(1)), collapse = ", "), "\n")

# --- Cubo recortado a la zona, 20 m
col <- stac_image_collection(items$features, asset_names = c("B03", "B11", "SCL"))
v <- cube_view(
  srs = "EPSG:32629",
  extent = list(t0 = as.character(fecha_prueba), t1 = as.character(fecha_prueba),
                left = unname(bb["xmin"]), right = unname(bb["xmax"]),
                bottom = unname(bb["ymin"]), top = unname(bb["ymax"])),
  dx = 20, dy = 20, dt = "P1D", aggregation = "first", resampling = "near"
)
cubo <- raster_cube(col, v)

dir.create("data/processed/sentinel2_prueba", showWarnings = FALSE, recursive = TRUE)
f <- write_tif(cubo, dir = "data/processed/sentinel2_prueba",
               prefix = paste0("s2_", fecha_prueba, "_"))
r <- rast(f[1])
names(r) <- c("B03", "B11", "SCL")

# --- Reflectancia (desde 2022-01-25 las imagenes llevan un desplazamiento de 1000)
off <- if (fecha_prueba >= as.Date("2022-01-25")) 1000 else 0
verde <- (r$B03 - off) / 10000
swir  <- (r$B11 - off) / 10000
mndwi <- (verde - swir) / (verde + swir)

# --- Pixeles validos segun SCL: 2 (zona oscura), 4-7 (vegetacion, suelo, agua, sin clasificar)
scl <- r$SCL
valido <- !is.na(scl) & (scl == 2 | (scl >= 4 & scl <= 7))

# --- Estadisticas dentro de la zona
dentro <- !is.na(rasterize(vect(zona), r))
n_zona   <- global(dentro, "sum", na.rm = TRUE)[1, 1]
n_valido <- global(dentro & valido, "sum", na.rm = TRUE)[1, 1]
n_agua   <- global(dentro & valido & (mndwi > 0), "sum", na.rm = TRUE)[1, 1]

cat("\n--- Resultado ---\n")
cat("Pixeles en la zona:           ", n_zona, "\n")
cat("Pixeles validos (sin nubes):  ", n_valido,
    sprintf("(%.1f %% de la zona)\n", 100 * n_valido / n_zona))
cat("Pixeles con agua (MNDWI > 0): ", n_agua,
    sprintf("(%.1f %% de los validos, %.0f ha)\n",
            100 * n_agua / n_valido, n_agua * 400 / 1e4))

# --- Mapa
clase <- ifel(valido, ifel(mndwi > 0, 2, 1), 0)
dir.create("figures", showWarnings = FALSE)
png(paste0("figures/prueba_agua_", fecha_prueba, ".png"), width = 1400, height = 1400, res = 200)
plot(clase, col = c("grey85", "tan", "steelblue"), legend = FALSE,
     main = paste("Agua (MNDWI > 0) en Donana,", format(fecha_prueba)))
plot(vect(zona), add = TRUE, border = "black", lwd = 1.5)
legend("bottomleft", fill = c("grey85", "tan", "steelblue"),
       legend = c("Nubes / sin dato", "Sin agua", "Agua"), bty = "n")
dev.off()
cat("Mapa guardado en figures/\n")
