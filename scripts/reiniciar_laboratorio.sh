#!/bin/bash
set -euo pipefail

PROJECT_DIR="$HOME/dba-sgd-pitr"
BACKUP_DIR="$HOME/dba-sgd-pitr-respaldo-20261029-193937/docker-volumes"

VOLUMES=(
  "dba-sgd-pitr_pgdata"
  "dba-sgd-pitr_pitrdata"
  "dba-sgd-pitr_pgbackrest_repo"
  "dba-sgd-pitr_pgbackrest_log"
)

echo "=========================================="
echo " REINICIO CONTROLADO DEL LABORATORIO PITR"
echo "=========================================="
echo "Proyecto: $PROJECT_DIR"
echo "Respaldo: $BACKUP_DIR"
echo
echo "Se exportarán estos volúmenes:"
printf ' - %s\n' "${VOLUMES[@]}"
echo
echo "ATENCION: se eliminarán los cuatro volúmenes"
echo "originales después de exportarlos."
echo

read -r -p "Escribe REINICIAR para continuar: " CONFIRM
if [[ "$CONFIRM" != "REINICIAR" ]]; then
  echo "Operación cancelada. No se eliminó nada."
  exit 0
fi

cd "$PROJECT_DIR"
mkdir -p "$BACKUP_DIR"

echo
echo "[1/5] Deteniendo y eliminando contenedores del proyecto..."
docker compose down

echo
echo "[2/5] Exportando volúmenes..."
for VOLUME in "${VOLUMES[@]}"; do
  docker volume inspect "$VOLUME" >/dev/null

  echo "Exportando $VOLUME ..."
  docker run --rm \
    -v "$VOLUME:/data:ro" \
    -v "$BACKUP_DIR:/backup" \
    alpine:3.20 \
    sh -c "cd /data && tar czf /backup/${VOLUME}.tar.gz ."

  test -s "$BACKUP_DIR/${VOLUME}.tar.gz"
  docker run --rm \
  -v "$BACKUP_DIR:/backup:ro" \
  alpine:3.20 \
  sh -c "tar -tzf /backup/${VOLUME}.tar.gz >/dev/null"

echo "Respaldo verificado: $VOLUME"

done

echo
echo "[3/5] Verificando archivos exportados..."
ls -lh "$BACKUP_DIR"

echo
echo "[4/5] Eliminando únicamente los volúmenes del laboratorio..."
docker volume rm "${VOLUMES[@]}"

echo
echo "[5/5] Creando nuevamente el volumen externo PITR..."
docker volume create dba-sgd-pitr_pitrdata

echo
echo "=========================================="
echo " LIMPIEZA COMPLETADA"
echo "=========================================="
echo "Los archivos del proyecto y results/ se conservaron."
echo "Los datos anteriores están exportados en:"
echo "$BACKUP_DIR"
echo
echo "No se han iniciado todavía los contenedores."
echo "Revisa el resultado antes de reconstruir el laboratorio."
