# 11_cruce_inundacion_lluvia_nivel.R
# Cruza la superficie inundada de la marisma (Sentinel-2, script 10) con la lluvia
# de Meteo Palacio y el nivel de agua de Cancela Millan (Hidromet), ya unidos en
# data/processed/lluvia_nivel_diario.csv (script 03).
# Solo lee ficheros ya generados: no descarga nada.

for (p in c("dplyr", "ggplot2", "tidyr")) {
  if (!requireNamespace(p, quietly = TRUE))
    stop("Falta el paquete ", p, ": install.packages('", p, "')")
}
library(dplyr); library(ggplot2); library(tidyr)

# --- Lectura (los CSV llevan lineas de comentario con la fuente y la licencia: '#')
serie <- read.csv("data/processed/sentinel2_serie/superficie_inundada_marisma.csv") |>
  mutate(fecha = as.Date(fecha))

dia <- read.csv("data/processed/lluvia_nivel_diario.csv", comment.char = "#") |>
  mutate(fecha = as.Date(fecha)) |>
  arrange(fecha) |>
  group_by(ano_hidro) |>
  mutate(lluvia_ano = cumsum(ifelse(is.na(lluvia_mm), 0, lluvia_mm))) |>  # desde inicio del ano hidrologico
  ungroup()

cat("Fechas de satelite:", nrow(serie), "\n")
cat("Dias con lluvia disponible:", sum(!is.na(dia$lluvia_mm)), "de", nrow(dia), "\n")
cat("Dias con nivel limpio disponible:", sum(!is.na(dia$nivel_limpio_m)), "de", nrow(dia), "\n")

# --- Lluvia acumulada en los k dias que acaban en cada fecha de satelite (incluida)
acum <- function(fechas, k) {
  vapply(fechas, function(x) {
    w <- dia$lluvia_mm[dia$fecha > x - k & dia$fecha <= x]
    if (all(is.na(w))) NA_real_ else sum(w, na.rm = TRUE)
  }, numeric(1))
}

cruce <- serie |>
  left_join(dia |> select(fecha, estado, nivel_limpio_m, lluvia_ano), by = "fecha") |>
  mutate(lluvia_7d  = acum(fecha, 7),
         lluvia_15d = acum(fecha, 15),
         lluvia_30d = acum(fecha, 30),
         lluvia_60d = acum(fecha, 60),
         lluvia_90d = acum(fecha, 90))

cat("\n--- Estado del nivel en las fechas de satelite ---\n")
print(table(cruce$estado, useNA = "ifany"))

cat("\n--- Tabla de cruce ---\n")
print(cruce |>
        transmute(fecha, pct_inundado,
                  lluvia_30d = round(lluvia_30d), lluvia_90d = round(lluvia_90d),
                  lluvia_ano = round(lluvia_ano),
                  nivel_m = round(nivel_limpio_m, 2), estado))

# --- Correlaciones de Spearman (pocas fechas y relacion no lineal)
vars <- c("lluvia_7d", "lluvia_15d", "lluvia_30d", "lluvia_60d", "lluvia_90d",
          "lluvia_ano", "nivel_limpio_m")
cor_tab <- do.call(rbind, lapply(vars, function(v) {
  ok <- complete.cases(cruce$pct_inundado, cruce[[v]])
  n <- sum(ok)
  if (n < 5) return(data.frame(variable = v, n = n, rho = NA, p = NA))
  ct <- suppressWarnings(cor.test(cruce$pct_inundado[ok], cruce[[v]][ok],
                                  method = "spearman", exact = FALSE))
  data.frame(variable = v, n = n, rho = round(unname(ct$estimate), 2),
             p = round(ct$p.value, 4))
}))
cat("\n--- Correlacion de Spearman con % de marisma inundada ---\n")
print(cor_tab)
cat("\nOjo: son series temporales con pocas fechas; los valores p son orientativos.\n")

# --- Guardado
write.csv(cruce, "data/processed/cruce_inundacion_lluvia_nivel.csv", row.names = FALSE)
write.csv(cor_tab, "data/processed/correlaciones_inundacion.csv", row.names = FALSE)

# --- Figura 1: tres paneles en el tiempo
dir.create("figures", showWarnings = FALSE)
rango <- range(cruce$fecha)
p_dia <- dia |> filter(fecha >= rango[1] - 30, fecha <= rango[2])
etq <- c("Marisma inundada (% del dominio, Sentinel-2)",
         "Lluvia diaria (mm, Meteo Palacio)",
         "Nivel de agua (m, Cancela Millan)")
d1 <- cruce |> transmute(fecha, valor = pct_inundado, panel = factor(etq[1], etq))
d2 <- p_dia |> transmute(fecha, valor = lluvia_mm, panel = factor(etq[2], etq))
d3 <- p_dia |> transmute(fecha, valor = nivel_limpio_m, panel = factor(etq[3], etq))

g1 <- ggplot() +
  geom_col(data = d2, aes(fecha, valor), fill = "grey40", width = 1) +
  geom_line(data = d3, aes(fecha, valor), colour = "darkgreen") +
  geom_line(data = d1, aes(fecha, valor), colour = "steelblue") +
  geom_point(data = d1, aes(fecha, valor), colour = "steelblue") +
  facet_wrap(~panel, ncol = 1, scales = "free_y") +
  theme_minimal() +
  labs(x = NULL, y = NULL,
       title = "Donana: inundacion de la marisma, lluvia y nivel de agua",
       caption = "Fuentes: Copernicus Sentinel-2 (Planetary Computer); ICTS-RBD / EBD-CSIC (Hidromet, Meteo Palacio)")
ggsave("figures/cruce_inundacion_lluvia_nivel.png", g1, width = 8, height = 8, dpi = 200)
suppressWarnings(print(g1))

# --- Figura 2: dispersion frente a lluvia de 60 dias y nivel
sc <- cruce |>
  select(fecha, pct_inundado, lluvia_60d, nivel_limpio_m) |>
  pivot_longer(c(lluvia_60d, nivel_limpio_m), names_to = "variable", values_to = "x") |>
  filter(!is.na(x)) |>
  mutate(variable = recode(variable,
                           lluvia_60d = "Lluvia acumulada 60 dias (mm)",
                           nivel_limpio_m = "Nivel Cancela Millan (m)"))
g2 <- ggplot(sc, aes(x, pct_inundado)) +
  geom_point(colour = "steelblue", size = 2.2) +
  facet_wrap(~variable, scales = "free_x") +
  theme_minimal() +
  labs(x = NULL, y = "% de marisma inundada",
       title = "Inundacion frente a lluvia y nivel de agua")
ggsave("figures/dispersion_inundacion.png", g2, width = 8, height = 4, dpi = 200)
suppressWarnings(print(g2))

cat("\nListo. Resultados en data/processed/ y figuras en figures/\n")
