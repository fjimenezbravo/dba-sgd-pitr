#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  COMPOSE_PROJECT_NAME="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' .env | tail -n 1)"
fi

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dba-sgd-pitr-demo}"
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
  echo "ERROR: COMPOSE_PROJECT_NAME contiene caracteres no permitidos."
  exit 1
}


COMPOSE=(docker compose -p "$COMPOSE_PROJECT_NAME" -f compose.demo.yaml)
CSV_PATH_FILE="results/post_incidente_csv.path"
LOG="results/reconciliacion_$(date '+%Y%m%d_%H%M%S').txt"

[[ -s "$CSV_PATH_FILE" ]] || {
  echo "ERROR: no existe la referencia al CSV generado por el script 05."
  exit 1
}

CSV="$(cat "$CSV_PATH_FILE")"

[[ -s "$CSV" ]] || {
  echo "ERROR: CSV inexistente o vacío: $CSV"
  exit 1
}

FILAS_CSV=$(($(wc -l < "$CSV") - 1))

if [[ "$FILAS_CSV" -ne 3 ]]; then
  echo "ERROR: el CSV debe contener exactamente 3 registros."
  echo "Registros encontrados: $FILAS_CSV"
  exit 1
fi

{
  echo "=== RECONCILIACION DE REGISTROS POSTERIORES ==="
  date
  echo
  echo "CSV utilizado: $CSV"

  EXISTENTES="$("${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db -Atc \
    "SELECT COUNT(*) FROM postulaciones WHERE observacion = 'POST_INCIDENTE_RECUPERABLE';")"

  if [[ "$EXISTENTES" != "0" ]]; then
    echo "ERROR: ya existen registros posteriores en recovery. Se cancela."
    exit 1
  fi

  TOTAL_RECOVERY="$("${COMPOSE[@]}" exec -T recovery psql \
    -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db -Atc \
    "SELECT COUNT(*) FROM postulaciones;")"

  if [[ "$TOTAL_RECOVERY" != "100" ]]; then
    echo "ERROR: recovery debe contener exactamente 100 registros antes de reconciliar."
    echo "Registros encontrados: $TOTAL_RECOVERY"
    exit 1
  fi

  echo "Recovery validado: 100 registros originales."

  echo
  echo "[1] Importando CSV en recovery (puerto 5433)"
  "${COMPOSE[@]}" exec -T recovery psql -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db \
    -c "\copy postulaciones (nombre_postulante, cargo, region, estado, creado_en, observacion) FROM STDIN WITH CSV HEADER" \
    < "$CSV"

  echo
  echo "[2] Validando resultado"
  "${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
    -c "SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE estado = 'rechazada') AS rechazadas, COUNT(*) FILTER (WHERE observacion = 'POST_INCIDENTE_RECUPERABLE') AS posteriores FROM postulaciones;"

  echo
  echo "[3] Verificando los tres registros reincorporados"
  "${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
    -c "SELECT nombre_postulante, cargo, region, estado, creado_en FROM postulaciones WHERE observacion = 'POST_INCIDENTE_RECUPERABLE' ORDER BY nombre_postulante;"

  TOTAL="$("${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db -Atc "SELECT COUNT(*) FROM postulaciones;")"
  POSTERIORES="$("${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db -Atc "SELECT COUNT(*) FROM postulaciones WHERE observacion = 'POST_INCIDENTE_RECUPERABLE';")"
  RECHAZADAS="$("${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db -Atc "SELECT COUNT(*) FROM postulaciones WHERE estado = 'rechazada';")"

  [[ "$TOTAL" == "103" && "$POSTERIORES" == "3" && "$RECHAZADAS" == "0" ]] || {
    echo "ERROR: la validación final no coincide con lo esperado."
    exit 1
  }

  echo
  echo "RECONCILIACION COMPLETADA: 103 registros, 3 posteriores y 0 rechazados."
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
