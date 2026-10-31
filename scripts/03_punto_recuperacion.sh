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

PUNTO="pitr_objetivo_$(date '+%Y%m%d_%H%M%S')"
LOG="results/punto_recuperacion_$(date '+%Y%m%d_%H%M%S').txt"

{
  echo "=== CREACION DEL PUNTO DE RECUPERACION PITR ==="
  date
  echo
  echo "[1] Hora del servidor PostgreSQL"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT clock_timestamp() AS hora_servidor;"
  echo
  echo "[2] Creando restore point: $PUNTO"
  LSN="$("${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db -Atc \
    "SELECT pg_create_restore_point('$PUNTO');")"
  echo "Restore point: $PUNTO"
  echo "LSN: $LSN"
  printf 'PUNTO=%s\nLSN=%s\n' "$PUNTO" "$LSN" > results/restore_point.env
  echo
  echo "PUNTO DE RECUPERACION CREADO CORRECTAMENTE"
  date
} 2>&1 | tee "$LOG"

echo "Datos guardados en results/restore_point.env"
echo "Evidencia guardada en: $LOG"
