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
SQL="scripts/simular_incidente.sql"

mkdir -p results

[[ -f results/restore_point.env ]] || {
  echo "ERROR: no existe el punto de recuperación."
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

LOG="results/incidente_$(date '+%Y%m%d_%H%M%S').txt"

{
  echo "=== SIMULACION DEL INCIDENTE ==="
  date
  echo
  echo "[2] Estado previo"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;"
  echo
  echo "[3] Ejecutando UPDATE accidental"
  "${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db < "$SQL"
  echo
  echo "[4] Verificando impacto"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT estado, COUNT(*) FROM postulaciones GROUP BY estado ORDER BY estado;"
  echo
  echo "INCIDENTE SIMULADO"
  date
} 2>&1 | tee "$LOG"

echo "Evidencia guardada en: $LOG"
