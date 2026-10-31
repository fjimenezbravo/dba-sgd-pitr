#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PROJECT="dba-sgd-pitr-demo"
if [[ -f "$ROOT_DIR/.env" ]]; then
    PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$ROOT_DIR/.env" | tail -n 1)"
    PROJECT="${PROJECT:-dba-sgd-pitr-demo}"
fi

# --auto ejecuta todas las etapas sin pausas (grabacion de respaldo, pruebas).
AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

pausa() {
    if [[ "$AUTO" -eq 0 ]]; then
        read -r -p "$1"
    fi
}
COMPOSE_FILE="$ROOT_DIR/compose.demo.yaml"
COMPOSE=(docker compose -p "$PROJECT" -f "$COMPOSE_FILE")

SCRIPTS=(
  "02_backup.sh"
  "03_cambios_legitimos.sh"
  "04_incidente.sh"
  "05_registros_posteriores.sh"
  "06_restaurar_pitr.sh"
  "07_reconciliar_post_incidente.sh"
  "08_validar_integridad.sh"
)

NOMBRES=(
  "Respaldo FULL con pgBackRest"
  "Cambios legítimos posteriores al respaldo"
  "Simulación del incidente"
  "Preservación de registros posteriores"
  "Recuperación PITR en instancia independiente"
  "Reconciliación de registros posteriores"
  "Validación de integridad"
)

RESUMENES=(
  "Respaldo FULL ejecutado y verificado."
  "Revisiones legítimas aplicadas después del respaldo FULL (solo vuelven vía WAL)."
  "Foto previa tomada; UPDATE accidental sobre los 100 registros con XID y hora registrados."
  "Tres registros posteriores preservados mediante CSV."
  "PITR hasta justo antes del COMMIT del incidente. Base recuperada en puerto 5433."
  "Tres registros posteriores reincorporados."
  "Los 100 registros recuperados son idénticos a la foto previa al UPDATE."
)

ESTADOS=(
  "PENDIENTE" "PENDIENTE" "PENDIENTE" "PENDIENTE"
  "PENDIENTE" "PENDIENTE" "PENDIENTE"
)

mostrar_checklist() {
    local completadas=0
    local j

    echo
    echo "========== CHECKLIST DE RECUPERACIÓN =========="

    for j in "${!SCRIPTS[@]}"; do
        case "${ESTADOS[$j]}" in
            COMPLETADO)
                echo "[✓] ${NOMBRES[$j]}"
                completadas=$((completadas + 1))
                ;;
            "EN CURSO")
                echo "[>] ${NOMBRES[$j]}  <-- EN CURSO"
                ;;
            *)
                echo "[ ] ${NOMBRES[$j]}"
                ;;
        esac
    done

    echo
    echo "Progreso: $completadas/${#SCRIPTS[@]} etapas completadas"
    echo "==============================================="
}

fallo() {
    local codigo=$?
    echo
    echo "[ERROR] La demostración se interrumpió."
    echo "Código de salida: $codigo"
    echo "El entorno se conserva para diagnóstico."
    exit "$codigo"
}

trap fallo ERR

echo
echo "=================================================="
echo "       DEMOSTRACIÓN DE RECUPERACIÓN PITR"
echo "       PostgreSQL 17 + pgBackRest"
echo "=================================================="

# --------------------------------------------------
# PREVALIDACIÓN
# --------------------------------------------------

echo
echo "========== PREVALIDACIÓN =========="

[[ -f "$COMPOSE_FILE" ]] || {
    echo "ERROR: No existe compose.demo.yaml."
    exit 1
}

[[ -f "$ROOT_DIR/.env" ]] || {
    echo "ERROR: No existe .env."
    exit 1
}

for SCRIPT in "${SCRIPTS[@]}"; do
    [[ -f "$ROOT_DIR/scripts/$SCRIPT" ]] || {
        echo "ERROR: No existe scripts/$SCRIPT."
        exit 1
    }
done

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker no está instalado o no está disponible."
    exit 1
}

docker info >/dev/null

# Comprueba que Compose y las variables sean válidos
"${COMPOSE[@]}" config -q

echo "[OK] Archivos, Docker y configuración verificados."

# --------------------------------------------------
# LIMPIEZA INICIAL DEL PROYECTO
# --------------------------------------------------

echo
echo "========== LIMPIEZA INICIAL =========="
echo "Proyecto exclusivo: $PROJECT"
echo "Se eliminarán los contenedores y volúmenes anteriores."
echo

pausa "Presiona ENTER para limpiar e iniciar el laboratorio..."

"${COMPOSE[@]}" down --volumes --remove-orphans

echo
echo "[OK] Entorno anterior del proyecto eliminado."

# --------------------------------------------------
# PREPARACIÓN DEL LABORATORIO
# --------------------------------------------------

echo
echo "========== PREPARACIÓN DEL LABORATORIO =========="

"${COMPOSE[@]}" up -d --build postgres

echo
echo "Esperando disponibilidad de PostgreSQL..."

DISPONIBLE=0

for intento in {1..60}; do
    if "${COMPOSE[@]}" exec -T postgres \
        pg_isready -U postgres -d postulaciones_db >/dev/null 2>&1; then
        DISPONIBLE=1
        break
    fi

    sleep 2
done

if [[ "$DISPONIBLE" -ne 1 ]]; then
    echo "ERROR: PostgreSQL no estuvo disponible en 120 segundos."
    exit 1
fi

echo "[OK] PostgreSQL principal disponible en puerto 5432."

# --------------------------------------------------
# EJECUCIÓN DE LAS SIETE ETAPAS
# --------------------------------------------------

for i in "${!SCRIPTS[@]}"; do

    SCRIPT="${SCRIPTS[$i]}"
    NOMBRE="${NOMBRES[$i]}"
    RUTA="$ROOT_DIR/scripts/$SCRIPT"

    ESTADOS[$i]="EN CURSO"

    mostrar_checklist

    echo
    echo "=================================================="
    echo "ETAPA $((i + 1))/${#SCRIPTS[@]}: $NOMBRE"
    echo "Script: $SCRIPT"
    echo "=================================================="
    echo

    pausa "Presiona ENTER para ejecutar esta etapa..."

    if bash "$RUTA"; then
        ESTADOS[$i]="COMPLETADO"

        echo
        echo "[OK] Etapa $((i + 1)) completada."
        echo "RESUMEN: ${RESUMENES[$i]}"

    else
        echo
        echo "[ERROR] Falló la etapa: $NOMBRE."
        echo "Se detiene la demostración."
        echo "No se ejecutará la limpieza."
        exit 1
    fi

    mostrar_checklist

    if (( i < ${#SCRIPTS[@]} - 1 )); then
        pausa "Presiona ENTER para continuar..."
    fi
done

# --------------------------------------------------
# RESULTADO FINAL
# --------------------------------------------------

echo
echo "=================================================="
echo "          RECUPERACIÓN COMPLETADA"
echo "=================================================="

mostrar_checklist

echo
echo "RESULTADOS FINALES"
echo "----------------------------------------------"
echo "PostgreSQL principal : puerto 5432"
echo "PostgreSQL recovery  : puerto 5433"
echo "Registros originales: 100"
echo "Registros posteriores: 3"
echo "Total reconciliado   : 103"
echo "Registros rechazados : 0"
echo "Integridad           : VALIDADA"
echo
echo "Evidencias disponibles en: results/"
echo
echo "Contenedores y volúmenes permanecen activos."
echo "No se ejecutará limpieza al finalizar."
echo
echo "=================================================="
echo "       FIN DE LA DEMOSTRACIÓN PITR"
echo "=================================================="




