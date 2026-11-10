# Fuentes de datos

Última actualización: 2026-11-10.

## Datos usados en el proyecto

| Dato | Fuente | Enlace | Fecha de descarga | Licencia | ¿Se sube al repo? |
|---|---|---|---|---|---|
| Nivel de agua medio diario, estación Cancela Millán (2022-01-01 a 2026-11-08) | ICTS-RBD / EBD-CSIC, Hidromet (portal y API) | https://datos-automaticos.icts-donana.es/ | 2026-11-09 (portal); 2026-11-10 (API) | CC BY 4.0 | Sí |
| Precipitación diaria, estación Palacio (1978-09-01 a 2026-11-08) | ICTS-RBD / EBD-CSIC, Meteo Palacio (portal y API) | https://meteorologia-palacio.icts-donana.es/ | 2026-11-09 (portal); 2026-11-10 (API) | CC BY 4.0 | Sí |
| Límite de la zona de estudio: Espacio Natural Doñana, Parque Nacional y Parque Natural (EENNPP, versión 2026_03) | REDIAM, Junta de Andalucía | https://portalrediam.cica.es/geonetwork/srv/api/records/6608ad36-f7a0-4b93-916f-ceb875459e57 | 2026-11-10 | CC BY 4.0 | Sí (el original pesa 5,8 MB) |
| Imágenes Sentinel-2 L2A (bandas B03, B11 y SCL; serie piloto 2024-10-27 a 2026-06-29) | Copernicus Sentinel-2 (ESA), vía Microsoft Planetary Computer | https://planetarycomputer.microsoft.com/dataset/sentinel-2-l2a | 2026-11-10 | Acceso libre y abierto (Copernicus) | No, por tamaño (solo los resultados derivados) |

## Fuentes previstas y no usadas por ahora

| Dato | Fuente | Estado |
|---|---|---|
| Censos de aves acuáticas | ICTS-Doñana, portal de censos (enlace desde https://icts-donana.csic.es/) | No descargado. Revisar la licencia antes de usarlo. |
| Precipitación regional (opcional) | AEMET OpenData | No descargado. |

## Citas recomendadas por las fuentes

- ICTS-RBD / EBD-CSIC (2026). Datos hidrometeorológicos de la red de monitorización de la Reserva Biológica de Doñana. Hidromet. Estación Biológica de Doñana (EBD-CSIC). Reserva Biológica de Doñana (ICTS-RBD). https://datos-automaticos.icts-donana.es/ (fecha de descarga: 2026-11-09)
- ICTS-RBD / EBD-CSIC (2026). Datos meteorológicos de la Estación Manual del Palacio de Doñana. Meteo Palacio. Estación Biológica de Doñana (EBD-CSIC). Reserva Biológica de Doñana (ICTS-RBD). https://meteorologia-palacio.icts-donana.es/ (fecha de descarga: 2026-11-09)
- REDIAM, Junta de Andalucía. Espacios Naturales Protegidos de Andalucía (EENNPP), versión 2026_03. (PENDIENTE: copiar la cita exacta de la ficha de la REDIAM, enlace en la tabla; fecha de descarga: 2026-11-10)
- Copernicus Sentinel-2 L2A, ESA. Accedido a través de Microsoft Planetary Computer. (PENDIENTE: copiar la redacción oficial de la atribución desde la ficha de Copernicus o Planetary Computer; fecha de descarga: 2026-11-10)

## Condiciones de reutilización (Aviso Legal ICTS-Doñana)

- No alterar el sentido de la información.
- Citar la fuente.
- Indicar la fecha de última actualización o consulta.

## Datos derivados (generados con los scripts de `scripts/`)

| Fichero | Script | ¿Se sube al repo? |
|---|---|---|
| `data/processed/hidromet_cancela_millan_nivel_diario.csv` | 03 | Sí |
| `data/processed/lluvia_nivel_diario.csv` (unión de lluvia y nivel, con columna `estado`) | 03 | Sí |
| `data/processed/zona_estudio_donana.gpkg`, `donana_figuras.gpkg`, `nucleo_parque_nacional_donana.gpkg` | 06 | Sí |
| `data/raw/sentinel2_catalogo/sentinel2_l2a_escenas_*.csv` (catálogo de escenas) | 07 | Sí |
| `data/processed/sentinel2_serie/estadisticas_por_fecha.csv` | 09 | Sí |
| `data/processed/sentinel2_serie/superficie_inundada_marisma.csv` | 10 | Sí |
| `data/processed/mascara_marisma.tif` | 10 | Revisar el tamaño antes de subirlo |
| `data/processed/cruce_inundacion_lluvia_nivel.csv`, `correlaciones_inundacion.csv` | 11 | Sí |
| `data/processed/sentinel2_clases/` y `data/processed/sentinel2_prueba/` (rásteres por fecha) | 08, 09 | No (en `.gitignore`, pesan mucho) |

## Calidad de los datos (detectada en el proyecto)

### Hidromet y Meteo Palacio

- Hidromet y Meteo Palacio son estaciones distintas (Cancela Millán y Palacio), no están en el mismo punto.
- Hidromet, nivel de agua: hueco sin datos del 2025-05-14 al 2026-01-15 (247 días) y el 2026-07-09. Desde el 2026-07-04 el valor salta de unos 0,03 m a unos 13,5 m y se queda plano; se marca como dudoso (`dudoso_salto_sensor`) hasta aclarar la causa con la ICTS-Doñana. Solo 12 de las 21 fechas de satélite usadas tienen nivel disponible.
- Meteo Palacio, lluvia: 262 días sin dato en toda la serie, 6 desde 2022. Los días sin dato no se rellenan.

### Sentinel-2

- El porcentaje de nubes del catálogo es de la escena entera, no de Doñana. Para enmascarar nubes se usa la banda SCL (se aceptan las clases 2 y 4 a 7).
- El catálogo devuelve a veces dos escenas por tesela y fecha (2.946 filas, 2.396 combinaciones fecha + tesela). Se deduplica al elegir fechas y el cubo toma una de las dos (`aggregation = "first"`).
- Serie piloto: una fecha por ventana de 30 días, la de menos nubes. 22 fechas entre 2024-10-27 y 2026-06-29. Se usan 21: se descarta el 2024-10-27 porque solo el 62,5 % de los píxeles del Parque Nacional son válidos (el corte es del 80 %).
- El agua se detecta con MNDWI > 0, a 20 m de resolución. Es un umbral aproximado, sin validar con datos de campo, salvo la comparación con el nivel de Cancela Millán (correlación de Spearman 0,94, 12 fechas).
- Con una fecha al mes se pueden perder picos cortos de inundación.

### Zona de estudio y marisma

- El límite de la marisma de Doñana está en disputa legal (deslinde). La zona de estudio (Espacio Natural Doñana, 127.707 ha según la REDIAM) es una zona de trabajo y no el deslinde legal de la marisma.
- El "dominio de marisma estacional" (25.128 ha) lo define este proyecto: píxeles del Parque Nacional con agua en al menos el 10 % de las fechas válidas, sin el agua permanente (más del 90 % de las fechas, 666 ha). Es una cifra propia del método, no oficial. El "% inundado" se calcula sobre ese dominio, de modo que los picos cercanos al 100 % son en parte efecto de cómo se define.

## Notas

- Los datos originales se guardan en `data/raw/` y no se modifican.
- Todo lo derivado se genera con los scripts de `scripts/`.
- Periodo analizado con Sentinel-2: 2024-10-27 a 2026-06-29 (serie piloto). La búsqueda en el catálogo se hizo desde 2022-01-01. Nivel de agua desde 2022-01-01 y lluvia desde 1978-09-01.
