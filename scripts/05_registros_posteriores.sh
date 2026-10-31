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

RUN_ID="$(date '+%Y%m%d_%H%M%S')"
LOG="results/post_incidente_${RUN_ID}.txt"
CSV="results/post_incidente_${RUN_ID}.csv"
CSV_PATH_FILE="results/post_incidente_csv.path"

{
  echo "=== REGISTROS LEGITIMOS POSTERIORES AL INCIDENTE ==="
  date
  echo

  echo "[1] Validando estado del incidente y registros previos"

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

  if [[ "$TOTAL" != "100" || "$AFECTADOS" != "100" || "$POSTERIORES" != "0" ]]; then
    echo "ERROR: estado no válido para insertar registros posteriores."
    echo "Total: $TOTAL | Afectados: $AFECTADOS | Posteriores: $POSTERIORES"
    exit 1
  fi

  if [[ -e "$CSV" ]]; then
    echo "ERROR: ya existe $CSV. Se cancela para proteger la evidencia."
    exit 1
  fi

  echo
  echo "[2] Insertando tres postulaciones legítimas"
  "${COMPOSE[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 \
    -U postgres -d postulaciones_db <<'SQL'
INSERT INTO postulaciones
    (nombre_postulante, cargo, region, estado, observacion)
VALUES
    ('Registro Posterior 1', 'Administrador de Bases de Datos',
     'Metropolitana', 'en_revision', 'POST_INCIDENTE_RECUPERABLE'),
    ('Registro Posterior 2', 'Analista de Datos',
     'Valparaiso', 'preseleccionada', 'POST_INCIDENTE_RECUPERABLE'),
    ('Registro Posterior 3', 'Ingeniero de Infraestructura',
     'Biobio', 'pendiente', 'POST_INCIDENTE_RECUPERABLE');
SQL

  echo
  echo "[3] Exportando registros posteriores a CSV"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "\copy (SELECT nombre_postulante, cargo, region, estado, creado_en, observacion FROM postulaciones WHERE observacion = 'POST_INCIDENTE_RECUPERABLE' ORDER BY nombre_postulante) TO STDOUT WITH CSV HEADER" \
    > "$CSV"

  FILAS_CSV=$(($(wc -l < "$CSV") - 1))
  if [[ "$FILAS_CSV" -ne 3 ]]; then
    echo "ERROR: el CSV debe contener exactamente 3 registros."
    exit 1
  fi

  printf '%s\n' "$CSV" > "$CSV_PATH_FILE"

  echo
  echo "[4] Verificando registros"
  "${COMPOSE[@]}" exec -T postgres psql -U postgres -d postulaciones_db \
    -c "SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE estado = 'rechazada') AS rechazadas, COUNT(*) FILTER (WHERE observacion = 'POST_INCIDENTE_RECUPERABLE') AS posteriores FROM postulaciones;"

  echo
  echo "[5] Forzando cambio de segmento WAL"
  "${COMPOSE[@]}" exec -T postgres psql \
    -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db \
    -c "SELECT pg_switch_wal();"

  echo "Solicitud de cambio de segmento WAL completada."
  echo
  echo "[6] Contenido del CSV"
  cat "$CSV"

  echo
  echo "REGISTROS POSTERIORES Y EXPORTACION COMPLETADOS"
  date
} 2>&1 | tee "$LOG"

echo "CSV generado: $CSV"
echo "Referencia guardada en: $CSV_PATH_FILE"
echo "Evidencia guardada en: $LOG"
