library(sf)
library(dplyr)
library(ggplot2)

f <- "data/raw/limite_renp/01_EENNPP/01_EENNPP/EENNPP_2026_03/InfGeografica/InfVectorial/Gpkg/EENNPP.gpkg"
x <- st_read(f, quiet = TRUE) |> st_make_valid()

# Los 4 poligonos de Donana
don <- x |>
  filter(grepl("do[ñn]ana", NOMBRE, ignore.case = TRUE)) |>
  mutate(ha = round(as.numeric(st_area(geom)) / 1e4))

cat("CRS:", st_crs(don)$input, "\n\n")
print(st_drop_geometry(don[, c("CODIGOESPA", "FIGURA", "ha")]))

# Comprobacion: Espacio Natural = Parque Nacional + Parque Natural?
pn  <- don |> filter(FIGURA == "Parque Nacional")
ppn <- don |> filter(FIGURA == "Parque Natural")
esp <- don |> filter(FIGURA == "Espacio Natural")
uni <- st_union(st_union(pn), st_union(ppn))
cat("\nSuperficie Espacio Natural (ha):", round(as.numeric(st_area(esp)) / 1e4), "\n")
cat("Superficie PN + PNat unidos (ha):", round(as.numeric(st_area(uni)) / 1e4), "\n")
cat("Diferencia simetrica (ha):",
    round(as.numeric(st_area(st_sym_difference(st_union(esp), uni))) / 1e4), "\n")

# Zona de estudio = Espacio Natural Donana
zona <- esp

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
st_write(don,  "data/processed/donana_figuras.gpkg", delete_dsn = TRUE, quiet = TRUE)
st_write(zona, "data/processed/zona_estudio_donana.gpkg", delete_dsn = TRUE, quiet = TRUE)

# Mapa
dir.create("figures", showWarnings = FALSE)
p <- ggplot() +
  geom_sf(data = don, aes(fill = FIGURA), alpha = 0.45, colour = "grey30") +
  geom_sf(data = zona, fill = NA, colour = "black", linewidth = 0.8) +
  theme_minimal() +
  labs(title = "Donana: figuras de proteccion", fill = NULL,
       caption = "Fuente: REDIAM, Junta de Andalucia (CC BY 4.0). ETRS89 / UTM 30N") +
  theme(legend.position = "bottom")
ggsave("figures/mapa_limite_donana.png", p, width = 7, height = 7, dpi = 200)
print(p)
