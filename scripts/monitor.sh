#!/usr/bin/env bash
# Monitor de solo lectura para la demostracion: consulta ambas instancias
# PostgreSQL cada pocos segundos y muestra disponibilidad, estados de las
# postulaciones, la postulacion 50 y el archivado de WAL.
# No modifica nada: la garantia de integridad la entrega 08_validar_integridad.sh.
#
# Uso: bash scripts/monitor.sh          (se actualiza cada 2 s; Ctrl+C para salir)
#      bash scripts/monitor.sh --once   (una sola lectura, para probar)
set -uo pipefail
# UTF-8 para que el ancho de las columnas cuente caracteres y no bytes
export LC_ALL=en_US.UTF-8

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
INTERVALO="${MONITOR_INTERVALO:-2}"
UNA_VEZ=0
[[ "${1:-}" == "--once" ]] && UNA_VEZ=1

ROJO=$'\033[1;31m'; VERDE=$'\033[1;32m'; AMARILLO=$'\033[1;33m'
GRIS=$'\033[0;90m'; NEGRITA=$'\033[1m'; NORMAL=$'\033[0m'

CONSULTA="SELECT pg_is_in_recovery(),
  COUNT(*),
  COUNT(*) FILTER (WHERE estado = 'rechazada'),
  COUNT(*) FILTER (WHERE estado = 'aprobada'),
  COUNT(*) FILTER (WHERE estado = 'preseleccionada'),
  COUNT(*) FILTER (WHERE estado = 'en_revision'),
  COUNT(*) FILTER (WHERE estado = 'pendiente'),
  COALESCE((SELECT estado FROM postulaciones WHERE id = 50), '-'),
  (SELECT timeline_id FROM pg_control_checkpoint())
FROM postulaciones;"

# Devuelve una linea "estado|recovery|total|rech|apro|pres|enrev|pend|p50|timeline"
leer_instancia() {
  local servicio="$1" fila
  if ! grep -qx "$servicio" <<< "$EN_EJECUCION"; then
    echo "detenida"
    return
  fi
  if ! fila="$("${COMPOSE[@]}" exec -T -e PGCONNECT_TIMEOUT=2 "$servicio" \
      psql -X -At -F '|' -U postgres -d postulaciones_db -c "$CONSULTA" 2>/dev/null)"; then
    echo "iniciando"
    return
  fi
  echo "ok|$fila"
}

leer_archivado() {
  grep -qx postgres <<< "$EN_EJECUCION" || return
  "${COMPOSE[@]}" exec -T -e PGCONNECT_TIMEOUT=2 postgres \
    psql -X -At -F '|' -U postgres -d postulaciones_db -c \
    "SELECT COALESCE(last_archived_wal, '-'),
            COALESCE(EXTRACT(EPOCH FROM now() - last_archived_time)::int::text, '-'),
            failed_count
     FROM pg_stat_archiver;" 2>/dev/null
}

# Ultima validacion de la etapa 7 de esta corrida (posterior al restore_point.env de la etapa 2)
leer_validacion() {
  local ultimo
  [[ -f results/restore_point.env ]] || { echo "pendiente"; return; }
  ultimo="$(ls -t results/integridad_*.txt 2>/dev/null | head -n 1)"
  if [[ -z "$ultimo" || ! "$ultimo" -nt results/restore_point.env ]]; then
    echo "pendiente"
  elif grep -q '^CORRECTO' "$ultimo"; then
    echo "CORRECTO|$(date -r "$ultimo" '+%H:%M:%S')"
  else
    echo "ERROR|$(date -r "$ultimo" '+%H:%M:%S')"
  fi
}

color_estado() {
  case "$1" in
    rechazada) printf '%s%s%s' "$ROJO" "$1" "$NORMAL" ;;
    aprobada)  printf '%s%s%s' "$VERDE" "$1" "$NORMAL" ;;
    *)         printf '%s' "$1" ;;
  esac
}

# Rellena a un ancho visible fijo (ignora los codigos de color)
celda() {
  local texto="$1" ancho="$2" visible
  visible="$(sed $'s/\033\\[[0-9;]*m//g' <<< "$texto")"
  printf '%s%*s' "$texto" $((ancho - ${#visible})) ''
}

columna() {
  # Arma las lineas de una instancia en el arreglo LINEAS
  local nombre="$1" dato="$2"
  local estado recov total rech apro pres enrev pend p50 tl
  IFS='|' read -r estado recov total rech apro pres enrev pend p50 tl <<< "$dato"
  LINEAS=("${NEGRITA}${nombre}${NORMAL}")
  case "$estado" in
    detenida)  LINEAS+=("${GRIS}○ detenida${NORMAL}"); return ;;
    iniciando) LINEAS+=("${AMARILLO}◐ iniciando${NORMAL}"); return ;;
  esac
  if [[ "$recov" == "t" ]]; then
    LINEAS+=("${AMARILLO}◐ recuperando WAL${NORMAL}")
  else
    LINEAS+=("${VERDE}● disponible${NORMAL} ${GRIS}TL ${tl}${NORMAL}")
  fi
  LINEAS+=("")
  LINEAS+=("$(celda "Total" 16)${NEGRITA}${total}${NORMAL}")
  if [[ "$rech" -gt 0 ]]; then
    LINEAS+=("$(celda "${ROJO}rechazada${NORMAL}" 16)${ROJO}${rech}${NORMAL}")
  else
    LINEAS+=("$(celda "rechazada" 16)${VERDE}${rech}${NORMAL}")
  fi
  LINEAS+=("$(celda "aprobada" 16)${apro}")
  LINEAS+=("$(celda "preseleccionada" 16)${pres}")
  LINEAS+=("$(celda "en_revision" 16)${enrev}")
  LINEAS+=("$(celda "pendiente" 16)${pend}")
  LINEAS+=("")
  LINEAS+=("Postulación 50")
  LINEAS+=("  $(color_estado "$p50")")
}

dibujar() {
  local principal recovery archivado validacion i max salida
  local wal edad fallos val hora_val
  EN_EJECUCION="$("${COMPOSE[@]}" ps --status running --services 2>/dev/null)"
  principal="$(leer_instancia postgres)"
  recovery="$(leer_instancia recovery)"
  archivado="$(leer_archivado)"
  # Sin base recuperada en linea no hay validacion de esta corrida que mostrar
  # (evita exhibir el resultado de una corrida anterior al inicio de la demo).
  if [[ "$recovery" == ok\|* ]]; then
    validacion="$(leer_validacion)"
  else
    validacion="pendiente"
  fi

  columna "PRINCIPAL :5432" "$principal"; local izq=("${LINEAS[@]}")
  columna "RECOVERY  :5433" "$recovery";  local der=("${LINEAS[@]}")
  max=${#izq[@]}; (( ${#der[@]} > max )) && max=${#der[@]}

  salida=" ${NEGRITA}MONITOR PITR · Conecta Rural${NORMAL}        $(date '+%H:%M:%S')\n"
  salida+=" ${GRIS}PostgreSQL 17 + pgBackRest · solo lectura${NORMAL}\n"
  salida+=" ──────────────────────────────────────────────────\n"
  for ((i = 0; i < max; i++)); do
    salida+=" $(celda "${izq[i]:-}" 26)${der[i]:-}\n"
  done
  salida+=" ──────────────────────────────────────────────────\n"

  if [[ -n "$archivado" ]]; then
    IFS='|' read -r wal edad fallos <<< "$archivado"
    if [[ "$edad" =~ ^[0-9]+$ && "$edad" -ge 120 ]]; then
      edad="$((edad / 60)) min"
    else
      edad="${edad} s"
    fi
    salida+=" WAL archivado: ${wal} ${GRIS}(hace ${edad} · fallos ${fallos})${NORMAL}\n"
  else
    salida+=" WAL archivado: ${GRIS}sin datos${NORMAL}\n"
  fi

  IFS='|' read -r val hora_val <<< "$validacion"
  case "$val" in
    CORRECTO) salida+=" Validación etapa 7: ${VERDE}CORRECTO${NORMAL} ${GRIS}(${hora_val})${NORMAL}\n" ;;
    ERROR)    salida+=" Validación etapa 7: ${ROJO}ERROR${NORMAL} ${GRIS}(${hora_val})${NORMAL}\n" ;;
    *)        salida+=" Validación etapa 7: ${GRIS}pendiente${NORMAL}\n" ;;
  esac

  if [[ "$UNA_VEZ" -eq 0 ]]; then
    printf '\033[H\033[J'
  fi
  printf '%b' "$salida"
}

if [[ "$UNA_VEZ" -eq 1 ]]; then
  dibujar
  exit 0
fi

trap 'printf "\033[?25h\n"; exit 0' INT TERM
printf '\033[?25l'
while true; do
  dibujar
  sleep "$INTERVALO"
done
