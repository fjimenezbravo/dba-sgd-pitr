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

if [[ ! -s "$RESTORE_ENV" ]]; then
  echo "ERROR: no existe el archivo del punto de recuperación o está vacío."
  exit 1
fi

source "$RESTORE_ENV"

# Objetivo de recuperacion (TARGET_TYPE):
#   xid  (por defecto) justo antes del COMMIT de la transaccion del incidente.
#   time hora del servidor al iniciar la transaccion del incidente.
#   name restore point preventivo del script 03 (plan B: pierde lo posterior).
TARGET_TYPE="${TARGET_TYPE:-xid}"

case "$TARGET_TYPE" in
  xid)
    TARGET="${XID_INCIDENTE:-}"
    TARGET_ARGS=(--type=xid --target="$TARGET" --target-exclusive)
    ;;
  time)
    TARGET="${HORA_INCIDENTE:-}"
    TARGET_ARGS=(--type=time --target="$TARGET" --target-exclusive)
    ;;
  name)
    TARGET="${PUNTO:-}"
    TARGET_ARGS=(--type=name --target="$TARGET")
    ;;
  *)
    echo "ERROR: TARGET_TYPE debe ser xid, time o name."
    exit 1
    ;;
esac

if [[ -z "$TARGET" ]]; then
  echo "ERROR: el objetivo '$TARGET_TYPE' no está definido en $RESTORE_ENV."
  exit 1
fi

LOG="results/restauracion_pitr_$(date '+%Y%m%d_%H%M%S').txt"
INICIO=0

{
  echo "=== RESTAURACION PITR POSTGRESQL 17 ==="
  date
  echo "Tipo de objetivo: $TARGET_TYPE"
  echo "Objetivo: $TARGET"
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
    "${TARGET_ARGS[@]}" \
    --target-action=promote \
    restore
  echo

  echo "[5] Iniciando PostgreSQL restaurado en puerto 5433"
  "${COMPOSE[@]}" up -d recovery

  # pg_isready acepta conexiones durante la recuperacion (hot standby):
  # la base solo esta disponible para escribir cuando termina y se promueve.
  echo "[6] Esperando fin de la recuperacion y promocion"
  LISTO=0
  for intento in $(seq 1 60); do
    if [[ "$("${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
          -Atc "SELECT pg_is_in_recovery();" 2>/dev/null)" == "f" ]]; then
      LISTO=1
      break
    fi
    sleep 1
  done

  if [[ "$LISTO" != "1" ]]; then
    echo "ERROR: PostgreSQL no terminó la recuperación dentro del tiempo esperado."
    "${COMPOSE[@]}" logs --tail 30 recovery
    exit 1
  fi

  FIN="$(date +%s)"
  RTO=$((FIN - INICIO))
  echo "Recuperacion terminada y base promovida."

  echo
  echo "[7] Verificando datos restaurados"
  "${COMPOSE[@]}" exec -T recovery psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;" \
    -c "SELECT id, estado, observacion FROM postulaciones WHERE id = 50;"

  echo
  echo "RESTAURACION PITR COMPLETADA"
  echo "Inicio epoch: $INICIO"
  echo "Fin epoch: $FIN"
  echo "RTO desde inicio de restauracion hasta base promovida: ${RTO} segundos"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
