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
mkdir -p results

# Restore point preventivo: es el plan B de la recuperación. El objetivo
# principal es la transacción del incidente (XID), que se registra en 04.
PUNTO="pitr_objetivo_$(date '+%Y%m%d_%H%M%S')"
LOG="results/cambios_legitimos_$(date '+%Y%m%d_%H%M%S').txt"

{
  echo "=== CAMBIOS LEGITIMOS POSTERIORES AL RESPALDO ==="
  date
  echo
  echo "Estos cambios ocurren despues del respaldo FULL: solo pueden volver"
  echo "si la recuperacion reproduce el WAL archivado, no basta el respaldo base."
  echo

  echo "[1] Estado antes de los cambios"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;"

  echo "[2] Revisores aprueban y preseleccionan postulaciones"
  "${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db <<'SQL'
UPDATE postulaciones
SET estado = 'aprobada',
    observacion = 'Revision legitima: aprobada por revisor'
WHERE id BETWEEN 1 AND 10;

UPDATE postulaciones
SET estado = 'preseleccionada',
    observacion = 'Revision legitima: preseleccionada por revisor'
WHERE id BETWEEN 11 AND 15;
SQL
  echo

  echo "[3] Estado despues de los cambios"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;"

  echo "[4] Creando restore point preventivo (plan B): $PUNTO"
  LSN="$("${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db -Atc \
    "SELECT pg_create_restore_point('$PUNTO');")"
  echo "LSN: $LSN"
  printf 'PUNTO=%s\nLSN=%s\n' "$PUNTO" "$LSN" > results/restore_point.env
  echo

  echo "CAMBIOS LEGITIMOS REGISTRADOS"
  date
} 2>&1 | tee "$LOG"

echo "Datos guardados en results/restore_point.env"
echo "Evidencia guardada en: $LOG"
