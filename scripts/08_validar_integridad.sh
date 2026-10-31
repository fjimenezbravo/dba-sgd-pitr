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
RESTORE_ENV="results/restore_point.env"
mkdir -p results
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -s "$RESTORE_ENV" ]] || {
  echo "ERROR: no existe $RESTORE_ENV."
  exit 1
}

source "$RESTORE_ENV"

[[ -n "${SNAPSHOT:-}" && -s "$SNAPSHOT" ]] || {
  echo "ERROR: no existe la foto previa al incidente (generada por el script 04)."
  exit 1
}

LOG="results/integridad_$(date '+%Y%m%d_%H%M%S').txt"
COLUMNAS="id, nombre_postulante, cargo, region, estado, creado_en, observacion"

{
  echo "=== VALIDACION DE INTEGRIDAD DE LOS 100 REGISTROS ORIGINALES ==="
  date
  echo "Referencia: $SNAPSHOT (foto tomada justo antes del UPDATE)"
  echo "Columnas comparadas: $COLUMNAS"

  echo
  echo "[1] Exportando registros originales de la base recuperada (5433)"
  "${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
    -c "\copy (SELECT $COLUMNAS FROM postulaciones WHERE id BETWEEN 1 AND 100 ORDER BY id) TO STDOUT WITH CSV HEADER" \
    > "$TMP/recovery.csv"

  echo
  echo "[2] Comprobando cantidad de filas"
  FILAS_FOTO=$(wc -l < "$SNAPSHOT" | tr -d ' ')
  FILAS_RECOVERY=$(wc -l < "$TMP/recovery.csv" | tr -d ' ')
  echo "Foto previa: $((FILAS_FOTO - 1)) registros"
  echo "Recovery:    $((FILAS_RECOVERY - 1)) registros"

  if [[ "$FILAS_FOTO" -ne 101 || "$FILAS_RECOVERY" -ne 101 ]]; then
    echo "ERROR: no se encontraron exactamente 100 registros originales en ambas fuentes."
    exit 1
  fi

  echo
  echo "[3] Comparando todas las columnas contra la foto previa"
  if diff -u "$SNAPSHOT" "$TMP/recovery.csv"; then
    echo "CORRECTO: los 100 registros recuperados son identicos al estado previo al UPDATE."
  else
    echo "ERROR: la base recuperada no coincide con el estado previo al UPDATE."
    exit 1
  fi

  echo
  echo "[4] Huella MD5 de ambos conjuntos"
  echo "Foto previa: $(md5sum < "$SNAPSHOT" 2>/dev/null || md5 -q "$SNAPSHOT")"
  echo "Recovery:    $(md5sum < "$TMP/recovery.csv" 2>/dev/null || md5 -q "$TMP/recovery.csv")"

  echo
  echo "[5] Contraste: la base principal sigue con el dano del incidente"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones WHERE id BETWEEN 1 AND 100 GROUP BY estado ORDER BY estado;"

  echo
  echo "VALIDACION DE INTEGRIDAD COMPLETADA"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
