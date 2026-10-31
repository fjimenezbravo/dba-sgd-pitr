#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for archivo in compose.yaml sql/01_schema.sql sql/02_datos_iniciales.sql; do
  if [[ ! -f "$archivo" ]]; then
    echo "ERROR: falta el archivo $archivo"
    exit 1
  fi
done

if [[ "${1:-}" != "--reiniciar-datos" ]]; then
  echo "Uso: $0 --reiniciar-datos"
  echo "Este script reinicia solo los datos de postulaciones."
  exit 2
fi
read -r -p "Escribe REINICIAR para continuar: " confirmacion
if [[ "$confirmacion" != "REINICIAR" ]]; then
  echo "Operacion cancelada."
  exit 0
fi

echo "Verificando PostgreSQL..."
docker compose exec -T postgres pg_isready -U postgres -d postulaciones_db

echo "Creando/verificando esquema..."
docker compose exec -T postgres psql \
  -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db \
  < sql/01_schema.sql
echo "Reiniciando datos de prueba..."
docker compose exec -T postgres psql \
  -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db \
  -c "TRUNCATE TABLE postulaciones RESTART IDENTITY;"

echo "Cargando datos iniciales..."
docker compose exec -T postgres psql \
  -v ON_ERROR_STOP=1 -U postgres -d postulaciones_db \
  < sql/02_datos_iniciales.sql

mkdir -p results
ARCHIVO="results/preparacion_$(date '+%Y%m%d_%H%M%S').txt"
{
  echo "Preparacion del escenario PITR"
  date
  echo
  docker compose exec -T postgres psql \
    -U postgres -d postulaciones_db \
    -c "SELECT COUNT(*) AS total_postulaciones FROM postulaciones;"
  echo
  docker compose exec -T postgres psql \
    -U postgres -d postulaciones_db \
    -c "SELECT id, nombre_postulante, cargo, region, estado, creado_en FROM postulaciones ORDER BY id LIMIT 10;"
} | tee "$ARCHIVO"

TOTAL="$(docker compose exec -T postgres psql \
  -U postgres -d postulaciones_db -Atc \
  "SELECT COUNT(*) FROM postulaciones;")"

if [[ "$TOTAL" != "100" ]]; then
  echo "ERROR: se esperaban 100 filas; se encontraron $TOTAL"
  exit 1
fi

echo "Preparacion completada: 100 postulaciones."
echo "Evidencia guardada en: $ARCHIVO"
