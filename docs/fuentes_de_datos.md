# Fuentes de datos

| Dato | Fuente | Enlace | Fecha de descarga | Licencia | ¿Se sube al repo? |
|---|---|---|---|---|---|
| Nivel de agua medio diario, estación Cancela Millán (2022-01-01 a 2026-11-08) | ICTS-RBD / EBD-CSIC, Hidromet | https://datos-automaticos.icts-donana.es/ | 2026-11-09 | CC BY 4.0 | Sí |
| Precipitación diaria, estación Palacio (1978-09-01 a 2026-11-08) | ICTS-RBD / EBD-CSIC, Meteo Palacio | https://meteorologia-palacio.icts-donana.es/ | 2026-11-09 | CC BY 4.0 | Sí |
| Censos de aves acuáticas | ICTS-Doñana, portal de censos | Enlace desde https://icts-donana.csic.es/ | (pendiente) | Revisar | No, hasta revisar |
| Imágenes Sentinel-2 L2A | Copernicus / Planetary Computer | (pendiente) | (pendiente) | (pendiente) | No |
| Límite de la zona de estudio | REDIAM, límites RENPA (Parque Nacional) | https://portalrediam.cica.es/geonetwork/srv/api/records/6608ad36-f7a0-4b93-916f-ceb875459e57 | (pendiente) | Revisar en la ficha | No, hasta revisar |
| Precipitación regional (opcional) | AEMET OpenData | (pendiente) | (pendiente) | (pendiente) | No |

## Citas recomendadas por las fuentes

- ICTS-RBD / EBD-CSIC (2026). Datos hidrometeorológicos de la red de monitorización de la Reserva Biológica de Doñana. Hidromet. Estación Biológica de Doñana (EBD-CSIC). Reserva Biológica de Doñana (ICTS-RBD). https://datos-automaticos.icts-donana.es/ (fecha de descarga: 2026-11-09)
- ICTS-RBD / EBD-CSIC (2026). Datos meteorológicos de la Estación Manual del Palacio de Doñana. Meteo Palacio. Estación Biológica de Doñana (EBD-CSIC). Reserva Biológica de Doñana (ICTS-RBD). https://meteorologia-palacio.icts-donana.es/ (fecha de descarga: 2026-11-09)

## Condiciones de reutilización (Aviso Legal ICTS-Doñana)

- No alterar el sentido de la información.
- Citar la fuente.
- Indicar la fecha de última actualización o consulta.

## Calidad de los datos (detectada en el proyecto)

- Hidromet y Meteo Palacio son estaciones distintas (Cancela Millán y Palacio), no están en el mismo punto.
- Hidromet, nivel de agua: hueco sin datos del 2025-05-14 al 2026-01-15 (247 días) y el 2026-07-09. Desde el 2026-07-04 el valor salta de unos 0,03 m a unos 13,5 m y se queda plano; se marca como dudoso hasta aclarar la causa con la ICTS-Doñana.
- Meteo Palacio, lluvia: 262 días sin dato en toda la serie, 6 desde 2022. Los días sin dato no se rellenan.
- El límite de la marisma de Doñana está en disputa legal (deslinde). La zona de estudio es una zona de trabajo y no el deslinde legal de la marisma.

## Notas

- Los datos originales se guardan en `data/raw/` y no se modifican.
- Todo lo derivado se genera con los scripts de `scripts/`.
- Periodo del proyecto: 2018-2026 (se confirmará según disponibilidad de Sentinel-2 L2A). La serie de nivel de agua descargada empieza en 2022.
