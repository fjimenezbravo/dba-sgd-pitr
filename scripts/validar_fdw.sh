#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p results

SALIDA="results/validacion_fdw.txt"

SQL="
WITH origen AS (
    SELECT nombre_postulante, cargo, region, estado, observacion
    FROM origen.postulaciones
    WHERE observacion = 'POST_INCIDENTE_RECUPERABLE'
),
recuperacion AS (
    SELECT nombre_postulante, cargo, region, estado, observacion
    FROM public.postulaciones
    WHERE observacion = 'POST_INCIDENTE_RECUPERABLE'
),
diferencias AS (
    (SELECT * FROM origen EXCEPT ALL SELECT * FROM recuperacion)
    UNION ALL
    (SELECT * FROM recuperacion EXCEPT ALL SELECT * FROM origen)
)
SELECT
    (SELECT COUNT(*) FROM origen),
    (SELECT COUNT(*) FROM recuperacion),
    (SELECT COUNT(*) FROM diferencias);
"

echo "Validación FDW - $(date '+%Y-%m-%d %H:%M:%S %Z')" | tee "$SALIDA"
echo "========================================" | tee -a "$SALIDA"

RESULTADO=$(docker compose exec -T recovery psql \
    -X -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db \
    -A -t -F '|' -c "$SQL")

echo "origen|recuperacion|diferencias" | tee -a "$SALIDA"
echo "$RESULTADO" | tee -a "$SALIDA"

if [[ "$RESULTADO" != "3|3|0" ]]; then
    echo "ERROR: la validación FDW no cumple los resultados esperados." | tee -a "$SALIDA"
    exit 1
fi

echo "OK: tres registros comparados y cero diferencias." | tee -a "$SALIDA"
