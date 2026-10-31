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

RESTORE_ENV="results/restore_point.env"

if [[ ! -s "$RESTORE_ENV" ]]; then
  echo "ERROR: no existe el archivo del punto de recuperación o está vacío."
  exit 1
fi

source "$RESTORE_ENV"

if [[ -z "${PUNTO:-}" || -z "${LSN:-}" ]]; then
  echo "ERROR: PUNTO o LSN no están definidos en $RESTORE_ENV."
  exit 1
fi
LOG="results/restauracion_pitr_$(date '+%Y%m%d_%H%M%S').txt"
INICIO=0

{
  echo "=== RESTAURACION PITR POSTGRESQL 17 ==="
  date
  echo "Restore point: $PUNTO"
  echo "LSN: $LSN"
  echo

  echo "[1] Comprobando disponibilidad de la base principal"
  "${COMPOSE[@]}" exec -T postgres \
    pg_isready -U postgres -d postulaciones_db

  echo "Base principal disponible."
  echo
  echo "[2] Comprobando que recovery esté detenido"

  if "${COMPOSE[@]}" ps --status running --services | grep -qx recovery; then
    echo "ERROR: recovery está ejecutándose. Se cancela para proteger los datos."
    exit 1
  fi

  echo "Recovery detenido."
  echo
  echo "[3] Comprobando destino de restauracion"
  "${COMPOSE[@]}" run --rm --no-deps --entrypoint sh recovery -c \
    'if [ -n "$(ls -A /var/lib/postgresql/data)" ]; then echo "ERROR: el volumen de recuperacion no esta vacio."; exit 1; fi; chown postgres:postgres /var/lib/postgresql/data'
  echo "Destino vacio y permisos preparados."
  echo

  echo "[4] Ejecutando restauracion PITR"
  INICIO="$(date +%s)"
  "${COMPOSE[@]}" run --rm --no-deps --user postgres \
    --entrypoint pgbackrest recovery \
    --stanza=main \
    --type=name \
    --target="$PUNTO" \
    --target-action=promote \
    restore
  echo

  echo "[5] Iniciando PostgreSQL restaurado en puerto 5433"
  "${COMPOSE[@]}" up -d recovery

  echo "[6] Esperando disponibilidad de PostgreSQL"
  LISTO=0
  for intento in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T recovery pg_isready -U postgres -d postulaciones_db; then
      LISTO=1
      break
    fi
    sleep 2
  done

  if [[ "$LISTO" != "1" ]]; then
    echo "ERROR: PostgreSQL no quedo disponible dentro del tiempo esperado."
    exit 1
  fi

  FIN="$(date +%s)"
  RTO=$((FIN - INICIO))

  echo
  echo "[7] Verificando datos restaurados"
  "${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
    -c "SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE estado = 'rechazada') AS rechazadas FROM postulaciones;"

  echo
  echo "RESTAURACION PITR COMPLETADA"
  echo "Inicio epoch: $INICIO"
  echo "Fin epoch: $FIN"
  echo "RTO hasta disponibilidad: ${RTO} segundos"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
