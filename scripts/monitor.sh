#!/usr/bin/env bash
# Monitor de solo lectura para la demostracion: consulta ambas instancias
# PostgreSQL cada pocos segundos y las compara con la foto tomada justo antes
# del incidente (etapa 3). Muestra disponibilidad, estados de las
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
RESTORE_ENV="results/restore_point.env"
INTERVALO="${MONITOR_INTERVALO:-2}"
UNA_VEZ=0
[[ "${1:-}" == "--once" ]] && UNA_VEZ=1

ROJO=$'\033[1;31m'; VERDE=$'\033[1;32m'; AMARILLO=$'\033[1;33m'
GRIS=$'\033[0;90m'; NEGRITA=$'\033[1m'; NORMAL=$'\033[0m'

ESTADOS=(rechazada aprobada preseleccionada en_revision pendiente)

CONSULTA="SELECT pg_is_in_recovery(),
  COUNT(*),
  COUNT(*) FILTER (WHERE estado = 'rechazada'),
  COUNT(*) FILTER (WHERE estado = 'aprobada'),
  COUNT(*) FILTER (WHERE estado = 'preseleccionada'),
  COUNT(*) FILTER (WHERE estado = 'en_revision'),
  COUNT(*) FILTER (WHERE estado = 'pendiente'),
  COALESCE((SELECT estado FROM postulaciones WHERE id = 50), '-'),
  (SELECT timeline_id FROM pg_control_checkpoint()),
  EXTRACT(EPOCH FROM pg_postmaster_start_time())::bigint
FROM postulaciones;"

# Linea "estado|recovery|total|rech|apro|pres|enrev|pend|p50|timeline|inicio"
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

# Foto previa al incidente (CSV de la etapa 3). Solo se usa si es de esta
# corrida: posterior al arranque de la base principal actual.
# Linea "ok|hora_foto|total|rech|apro|pres|enrev|pend|p50|hora_error|xid" o "pendiente"
leer_foto() {
  local inicio_principal="$1" snapshot="" xid="" hora="" hora_error="-" seg
  [[ -f "$RESTORE_ENV" ]] || { echo "pendiente"; return; }
  snapshot="$(sed -n 's/^SNAPSHOT=//p' "$RESTORE_ENV" | tail -n 1)"
  xid="$(sed -n 's/^XID_INCIDENTE=//p' "$RESTORE_ENV" | tail -n 1)"
  hora="$(sed -n 's/^HORA_INCIDENTE="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$RESTORE_ENV" | tail -n 1)"
  if [[ -z "$snapshot" || ! -f "$snapshot" || -z "$inicio_principal" ]] \
     || (( $(stat -f %m "$snapshot") < inicio_principal )); then
    echo "pendiente"
    return
  fi
  # Hora del servidor (UTC) del incidente, convertida a hora local
  seg="$(date -j -u -f '%Y-%m-%d %H:%M:%S' "${hora%%.*}" '+%s' 2>/dev/null)" \
    && hora_error="$(date -r "$seg" '+%H:%M:%S')"
  awk -F',' -v hf="$(date -r "$snapshot" '+%H:%M:%S')" -v he="$hora_error" -v xid="$xid" '
    NR > 1 { total++; n[$5]++; if ($1 == 50) p50 = $5 }
    END {
      printf "ok|%s|%d|%d|%d|%d|%d|%d|%s|%s|%s\n", hf, total,
        n["rechazada"], n["aprobada"], n["preseleccionada"], n["en_revision"],
        n["pendiente"], (p50 == "" ? "-" : p50), he, xid
    }' "$snapshot"
}

# Ultima validacion de la etapa 7 de esta corrida (posterior al restore_point.env de la etapa 2)
leer_validacion() {
  local ultimo
  [[ -f "$RESTORE_ENV" ]] || { echo "pendiente"; return; }
  ultimo="$(ls -t results/integridad_*.txt 2>/dev/null | head -n 1)"
  if [[ -z "$ultimo" || ! "$ultimo" -nt "$RESTORE_ENV" ]]; then
    echo "pendiente"
  elif grep -q '^CORRECTO' "$ultimo"; then
    echo "CORRECTO|$(date -r "$ultimo" '+%H:%M:%S')"
  else
    echo "ERROR|$(date -r "$ultimo" '+%H:%M:%S')"
  fi
}

# Rellena a un ancho visible fijo (ignora los codigos de color)
celda() {
  local texto="$1" ancho="$2" visible
  visible="$(sed $'s/\033\\[[0-9;]*m//g' <<< "$texto")"
  printf '%s%*s' "$texto" $((ancho - ${#visible})) ''
}

color_estado() {
  case "$1" in
    rechazada)       printf '%s%s%s' "$ROJO" "$1" "$NORMAL" ;;
    aprobada)        printf '%s%s%s' "$VERDE" "$1" "$NORMAL" ;;
    preseleccionada) printf 'preselecc.' ;;
    *)               printf '%s' "$1" ;;
  esac
}

# Rellena el arreglo C (una celda por fila de la tabla) para una columna.
# $1: tipo (foto|base), $2: datos, $3: subtitulo (hora o puerto)
columna() {
  local tipo="$1" dato="$2" subtitulo="$3"
  local estado a b total rech apro pres enrev pend p50 tl
  C=()
  if [[ "$tipo" == "foto" ]]; then
    IFS='|' read -r estado a total rech apro pres enrev pend p50 b <<< "$dato"
    C+=("$subtitulo")
    if [[ "$estado" != "ok" ]]; then
      C+=("" "${GRIS}pendiente${NORMAL}")
      return
    fi
    C+=("${a}" "foto previa" "-")
  else
    IFS='|' read -r estado recov total rech apro pres enrev pend p50 tl b <<< "$dato"
    C+=("$subtitulo")
    case "$estado" in
      detenida)  C+=("${GRIS}" "${GRIS}○ detenida${NORMAL}"); return ;;
      iniciando) C+=("" "${AMARILLO}◐ iniciando${NORMAL}"); return ;;
    esac
    C+=("")
    if [[ "$recov" == "t" ]]; then
      C+=("${AMARILLO}◐ aplicando${NORMAL}")
    else
      C+=("${VERDE}● en línea${NORMAL}")
    fi
    C+=("$tl")
  fi
  C+=("${NEGRITA}${total}${NORMAL}")
  if [[ "$tipo" == "base" && "$rech" -gt 0 ]]; then
    C+=("${ROJO}${rech}${NORMAL}")
  elif [[ "$tipo" == "base" ]]; then
    C+=("${VERDE}${rech}${NORMAL}")
  else
    C+=("$rech")
  fi
  C+=("$apro" "$pres" "$enrev" "$pend" "$(color_estado "$p50")")
}

dibujar() {
  local principal recovery foto archivado validacion inicio i salida
  local wal edad fallos val hora_val f_estado f_hora f_he f_xid
  EN_EJECUCION="$("${COMPOSE[@]}" ps --status running --services 2>/dev/null)"
  principal="$(leer_instancia postgres)"
  recovery="$(leer_instancia recovery)"
  inicio="$(awk -F'|' '$1 == "ok" { print $11 }' <<< "$principal")"
  foto="$(leer_foto "$inicio")"
  archivado="$(leer_archivado)"
  # Sin base recuperada en linea no hay validacion de esta corrida que mostrar
  # (evita exhibir el resultado de una corrida anterior al inicio de la demo).
  if [[ "$recovery" == ok\|* ]]; then
    validacion="$(leer_validacion)"
  else
    validacion="pendiente"
  fi

  columna foto "$foto" "${NEGRITA}ANTES${NORMAL}";            local c1=("${C[@]}")
  columna base "$principal" "${NEGRITA}PRINCIPAL${NORMAL}";   local c2=("${C[@]}")
  columna base "$recovery" "${NEGRITA}RECOVERY${NORMAL}";     local c3=("${C[@]}")
  # Segunda fila del encabezado: hora de la foto o puerto de la base
  [[ "$foto" == ok\|* ]] || c1[1]="${GRIS}-${NORMAL}"
  c2[1]="${GRIS}:5432${NORMAL}"
  c3[1]="${GRIS}:5433${NORMAL}"

  local etiquetas=("" "" "Estado" "Línea de tiempo" "Total" "rechazada" "aprobada" \
                   "preseleccionada" "en_revision" "pendiente" "Postulación 50")

  salida=" ${NEGRITA}MONITOR PITR · Conecta Rural${NORMAL}      $(date '+%d-%m-%Y %H:%M:%S')\n"
  salida+=" ${GRIS}PostgreSQL 17 + pgBackRest · solo lectura${NORMAL}\n"
  salida+=" ─────────────────────────────────────────────────────\n"
  for ((i = 0; i < ${#etiquetas[@]}; i++)); do
    [[ $i -eq 4 || $i -eq 10 ]] && salida+="\n"
    salida+=" $(celda "${etiquetas[i]}" 17)$(celda "${c1[i]:-}" 12)$(celda "${c2[i]:-}" 12)${c3[i]:-}\n"
  done
  salida+=" ─────────────────────────────────────────────────────\n"

  if [[ "$foto" == ok\|* ]]; then
    IFS='|' read -r f_estado f_hora _ _ _ _ _ _ _ f_he f_xid <<< "$foto"
    salida+=" Foto previa ${f_hora} · error ${ROJO}${f_he}${NORMAL} ${GRIS}(XID ${f_xid})${NORMAL}\n"
  else
    salida+=" Foto previa: ${GRIS}se toma en la etapa 3, justo antes del error${NORMAL}\n"
  fi

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
