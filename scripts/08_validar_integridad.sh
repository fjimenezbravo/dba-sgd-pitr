#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  COMPOSE_PROJECT_NAME="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' .env | tail -n 1)"
fi

COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME"
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
  echo "ERROR: COMPOSE_PROJECT_NAME contiene caracteres no permitidos."
  exit 1
}


COMPOSE=(docker compose -p "$COMPOSE_PROJECT_NAME" -f compose.demo.yaml)
mkdir -p results
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LOG="results/integridad_$(date '+%Y%m%d_%H%M%S').txt"

{
  echo "=== VALIDACION DE INTEGRIDAD DE LOS 100 REGISTROS ORIGINALES ==="
  date

  echo
  echo "[1] Exportando registros originales de la base principal (5432)"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "\copy (SELECT id, nombre_postulante, cargo, region, creado_en FROM postulaciones WHERE id BETWEEN 1 AND 100 ORDER BY id) TO STDOUT WITH CSV HEADER" \
    > "$TMP/principal.csv"

  echo
  echo "[2] Exportando registros originales de la base recuperada (5433)"
  "${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
    -c "\copy (SELECT id, nombre_postulante, cargo, region, creado_en FROM postulaciones WHERE id BETWEEN 1 AND 100 ORDER BY id) TO STDOUT WITH CSV HEADER" \
    > "$TMP/recovery.csv"

  echo
  echo "[3] Comprobando cantidad de filas"
  FILAS_PRINCIPAL=$(wc -l < "$TMP/principal.csv" | tr -d ' ')
  FILAS_RECOVERY=$(wc -l < "$TMP/recovery.csv" | tr -d ' ')
  echo "Principal: $((FILAS_PRINCIPAL - 1)) registros"
  echo "Recovery: $((FILAS_RECOVERY - 1)) registros"

  if [[ "$FILAS_PRINCIPAL" -ne 101 || "$FILAS_RECOVERY" -ne 101 ]]; then
    echo "ERROR: no se encontraron exactamente 100 registros originales en ambas bases."
    exit 1
  fi

  echo
  echo "[4] Comparando campos originales"
  if diff -u "$TMP/principal.csv" "$TMP/recovery.csv"; then
    echo "CORRECTO: los 100 registros originales coinciden exactamente."
  else
    echo "ERROR: existen diferencias en los campos originales."
    exit 1
  fi

  echo
  echo "VALIDACION DE INTEGRIDAD COMPLETADA"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
