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
SQL="scripts/simular_incidente.sql"

mkdir -p results

[[ -f results/restore_point.env ]] || {
  echo "ERROR: no existe results/restore_point.env (ejecute el script 03)."
  exit 1
}

[[ -f "$SQL" ]] || {
  echo "ERROR: no existe $SQL"
  exit 1
}

echo "[1] Validando estado previo del laboratorio"

ESTADO="$("${COMPOSE[@]}" exec -T postgres psql \
  -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db -Atc "
    SELECT
      COUNT(*),
      COUNT(*) FILTER (
        WHERE estado = 'rechazada'
          AND observacion = 'INCIDENTE: UPDATE accidental sin WHERE'
      ),
      COUNT(*) FILTER (
        WHERE observacion = 'POST_INCIDENTE_RECUPERABLE'
      )
    FROM postulaciones;
  ")"

IFS='|' read -r TOTAL AFECTADOS POSTERIORES <<< "$ESTADO"

if [[ "$TOTAL" != "100" || "$AFECTADOS" != "0" || "$POSTERIORES" != "0" ]]; then
  echo "ERROR: estado no válido para ejecutar el incidente."
  echo "Total: $TOTAL | Afectados: $AFECTADOS | Posteriores: $POSTERIORES"
  echo "Se cancela para proteger los datos."
  exit 1
fi

RUN_ID="$(date '+%Y%m%d_%H%M%S')"
LOG="results/incidente_${RUN_ID}.txt"
SNAPSHOT="results/antes_incidente_${RUN_ID}.csv"

{
  echo "=== SIMULACION DEL INCIDENTE ==="
  date
  echo

  # Cambio legitimo segundos antes del incidente: si la recuperacion queda
  # "justo antes del UPDATE", este cambio debe volver; si queda antes, se pierde.
  echo "[2] Ultimo cambio legitimo antes del incidente (id 50)"
  "${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db -c "
      UPDATE postulaciones
      SET estado = 'aprobada',
          observacion = 'Revision legitima: aprobada segundos antes del incidente'
      WHERE id = 50;"
  echo

  echo "[3] Foto del estado previo (todas las columnas): $SNAPSHOT"
  "${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db \
    -c "\copy (SELECT id, nombre_postulante, cargo, region, estado, creado_en, observacion FROM postulaciones ORDER BY id) TO STDOUT WITH CSV HEADER" \
    > "$SNAPSHOT"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;"

  sleep 2

  echo "[4] Ejecutando UPDATE accidental (hora del servidor y XID registrados)"
  SALIDA="$("${COMPOSE[@]}" exec -T postgres psql -X -At -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db < "$SQL")"
  echo "$SALIDA"

  XID_INCIDENTE="$(sed -n 's/^XID_INCIDENTE=//p' <<< "$SALIDA")"
  HORA_INCIDENTE="$(sed -n 's/^HORA_INCIDENTE=//p' <<< "$SALIDA")"

  if [[ -z "$XID_INCIDENTE" || -z "$HORA_INCIDENTE" ]]; then
    echo "ERROR: no se pudo registrar el XID o la hora del incidente."
    exit 1
  fi

  printf 'XID_INCIDENTE=%s\nHORA_INCIDENTE="%s"\nSNAPSHOT=%s\n' \
    "$XID_INCIDENTE" "$HORA_INCIDENTE" "$SNAPSHOT" >> results/restore_point.env
  echo

  echo "[5] Verificando impacto"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;"
  echo
  echo "INCIDENTE SIMULADO"
  echo "XID del incidente : $XID_INCIDENTE"
  echo "Hora del incidente: $HORA_INCIDENTE"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
