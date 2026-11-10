# 10_mascara_marisma.R
# Mascara de marisma (inundacion estacional) y curva de superficie inundada.
# Usa los rasters de clases del script 09 (0 = nube, 1 = sin agua, 2 = agua).

for (p in c("terra", "sf", "dplyr", "ggplot2")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("Falta el paquete ", p, ": install.packages('", p, "')")
}
library(terra); library(sf); library(dplyr); library(ggplot2)

umbral_valido <- 80    # % minimo de pixeles validos en el Parque Nacional
umbral_min    <- 0.10  # fraccion minima de fechas con agua para ser marisma
umbral_perm   <- 0.90  # por encima de esto = agua permanente
min_fechas    <- 5     # fechas validas minimas por pixel

stats <- read.csv("data/processed/sentinel2_serie/estadisticas_por_fecha.csv")
buenas <- stats |>
  filter(figura == "Parque Nacional", pct_valido >= umbral_valido) |>
  pull(fecha)
cat("Fechas usadas:", length(buenas), "de", n_distinct(stats$fecha), "\n")

fich <- file.path("data/processed/sentinel2_clases", paste0("clase_", buenas, ".tif"))
fich <- fich[file.exists(fich)]
r <- rast(fich)
names(r) <- sub("clase_", "", tools::file_path_sans_ext(basename(fich)))
r <- ifel(r == 0, NA, r)            # nubes y sin dato -> NA

# Frecuencia de agua por pixel
n_valid <- sum(!is.na(r))
n_agua  <- sum(r == 2, na.rm = TRUE)
freq <- n_agua / n_valid
freq <- ifel(n_valid < min_fechas, NA, freq)

# Solo dentro del Parque Nacional
pn <- st_read("data/processed/nucleo_parque_nacional_donana.gpkg", quiet = TRUE) |>
  st_transform(32629)
en_pn <- !is.na(rasterize(vect(pn), r[[1]]))

# 1 = casi nunca agua (dunas, pinar), 2 = inundacion estacional, 3 = agua permanente
tipo <- ifel(en_pn & !is.na(freq),
             ifel(freq >= umbral_perm, 3, ifel(freq >= umbral_min, 2, 1)),
             NA)
marisma <- (tipo == 2)

n_dom <- global(marisma, "sum", na.rm = TRUE)[1, 1]
ha_dom <- n_dom * 400 / 1e4
cat(sprintf("Dominio de marisma estacional: %.0f ha\n", ha_dom))
cat(sprintf("Agua permanente: %.0f ha\n",
            global(tipo == 3, "sum", na.rm = TRUE)[1, 1] * 400 / 1e4))

# Superficie inundada por fecha dentro de la marisma
serie <- do.call(rbind, lapply(seq_len(nlyr(r)), function(i) {
  ri <- r[[i]]
  nv <- global(marisma & !is.na(ri), "sum", na.rm = TRUE)[1, 1]
  na <- global(marisma & (ri == 2), "sum", na.rm = TRUE)[1, 1]
  data.frame(fecha = as.Date(names(r)[i]),
             pct_validos_marisma = round(100 * nv / n_dom, 1),
             pct_inundado = round(100 * na / nv, 1),
             ha_inundada_est = round(100 * na / nv / 100 * ha_dom))
}))
print(serie)

dir.create("data/processed/sentinel2_serie", showWarnings = FALSE, recursive = TRUE)
write.csv(serie, "data/processed/sentinel2_serie/superficie_inundada_marisma.csv",
          row.names = FALSE)
writeRaster(tipo, "data/processed/mascara_marisma.tif", datatype = "INT1U", overwrite = TRUE)

# Figuras
dir.create("figures", showWarnings = FALSE)
png("figures/mascara_marisma.png", width = 1400, height = 1400, res = 200)
plot(tipo, col = c("grey90", "skyblue", "navy"), range = c(1, 3), legend = FALSE,
     main = "Mascara de marisma (Parque Nacional de Donana)")
legend("bottomleft", fill = c("grey90", "skyblue", "navy"), bty = "n",
       legend = c("Casi nunca agua", "Inundacion estacional", "Agua permanente"))
dev.off()

g <- ggplot(serie, aes(fecha, pct_inundado)) +
  geom_line(colour = "steelblue") + geom_point(colour = "steelblue") +
  theme_minimal() +
  labs(title = "Marisma de Donana: porcentaje inundado (Sentinel-2, MNDWI > 0)",
       x = NULL, y = "% de la marisma estacional inundada",
       caption = "Fuente: Copernicus Sentinel-2 L2A (Planetary Computer)")
ggsave("figures/curva_inundacion.png", g, width = 8, height = 4.5, dpi = 200)
print(g)
