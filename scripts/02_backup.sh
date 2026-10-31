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
LOG="results/backup_$(date '+%Y%m%d_%H%M%S').txt"

{
  echo "=== BACKUP COMPLETO PostgreSQL / pgBackRest ==="
  date
  echo

  echo "[1] Verificando PostgreSQL"
  "${COMPOSE[@]}" exec -T postgres pg_isready -U postgres -d postulaciones_db
  echo

  echo "[2] Verificando registros iniciales"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT COUNT(*) AS total FROM postulaciones;"

  TOTAL="$("${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db -Atc "SELECT COUNT(*) FROM postulaciones;")"

  if [[ "$TOTAL" != "100" ]]; then
    echo "ERROR: se esperaban 100 registros y se encontraron $TOTAL"
    exit 1
  fi
  echo

  echo "[3] Verificando stanza pgBackRest"
  if "${COMPOSE[@]}" exec -T -u postgres postgres \
      test -f /var/lib/pgbackrest/backup/main/backup.info; then
    echo "Stanza main existente. Se continúa."
  else
    echo "Stanza main no encontrada. Inicializando automáticamente..."
    "${COMPOSE[@]}" exec -T -u postgres postgres \
      pgbackrest --stanza=main stanza-create
  fi
  echo

  echo "[4] Creando backup FULL"
  "${COMPOSE[@]}" exec -T -u postgres postgres \
    pgbackrest --stanza=main backup --type=full
  echo

  echo "[5] Verificando backup"
  "${COMPOSE[@]}" exec -T -u postgres postgres \
    pgbackrest --stanza=main info
  echo

  echo "BACKUP COMPLETADO CORRECTAMENTE"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
