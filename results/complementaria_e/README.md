# Prueba complementaria E: pérdida simulada del origen

Esta prueba **no es parte de la demo oficial** y no usa sus contenedores, volúmenes ni scripts. La
demo oficial recupera la base de un **error lógico** (`UPDATE` sin `WHERE`) con PITR. La prueba E
responde otra pregunta: si la base de origen se pierde de golpe, ¿cuánto de lo confirmado se puede
recuperar solo desde el repositorio de respaldos y WAL archivado?

## Entorno

- Proyecto Docker Compose aislado (`dba-sgd-archivo`), con su propio contenedor, volúmenes y stanza
  de pgBackRest. Antes y después de la prueba se tomó una foto de la demo, que quedó idéntica
  (`*_demo_antes.txt` y `*_demo_despues.txt`).
- PostgreSQL 17.11, pgBackRest 2.60.0, `archive_timeout=60s`, segmentos de WAL de 16 MB.
- **Repositorio local**, en el mismo equipo y no en otro servidor físico.
- Ejecución del 1 de noviembre de 2026 a las 08:35 (hora de Chile).

## Procedimiento

1. Respaldo FULL en el repositorio aislado.
2. Carga sostenida durante 30 s: unas 90 transacciones por segundo de 64 KB cada una, desde un
   cliente en **otro contenedor**. Por cada transacción, el cliente registra **fuera de Docker**:
   - `P`: el id insertado, antes del COMMIT;
   - `C`: el COMMIT acusado por el servidor;
   - la hora y el LSN posteriores al COMMIT.
3. `docker kill` del contenedor de origen, en seco.
4. Restauración en **otra instancia** con `pgbackrest restore --type=default`. Esa instancia solo
   monta un volumen vacío, el repositorio en solo lectura y la configuración, nunca el volumen de
   origen.
5. Comparación de los **conjuntos completos** de ids registrados frente a los ids presentes en la
   base restaurada.

## Resultados

| Concepto | Valor |
|---|---|
| Transacciones intentadas (`P`) | 2.740 |
| Confirmadas (`C`, COMMIT acusado) | **2.740** |
| Recuperadas | **2.611** (ids 1–2611) |
| Perdidas | **129** (ids 2612–2740) |
| Indeterminadas (COMMIT enviado sin acuse) | 0 |
| Anomalías (ids recuperados sin intento registrado) | 0 |
| Última confirmada recuperada | id 2611, confirmada 1,41 s antes de la detención |
| Ventana de pérdida observada | confirmadas entre 1,39 s y 0,09 s antes de la detención: **~1,4 s** de actividad |
| Restauración técnica | **2,2 s**: copia con pgBackRest 1,2 s + recuperación y promoción 1,0 s |

**Cómo se calcula cada categoría:**
- *Recuperadas*: confirmadas cuyo id está en la base restaurada.
- *Perdidas*: confirmadas cuyo id no está en la base restaurada.
- *Indeterminadas*: ids con `P` pero sin `C`.

Las perdidas forman un bloque final contiguo. Todas tienen su commit después del último segmento
archivado (`…10`, según `pgbackrest info`), en el segmento `…11`, que no alcanzó a archivarse; todas
las recuperadas tienen su commit antes de ese límite.

**Integridad:**
- `pgbackrest verify`: OK. Revisa el repositorio; no reemplaza la restauración.
- `pg_amcheck` sobre la base restaurada: sin corrupción.
- La base restaurada tiene 2.611 filas con 2.611 ids distintos.

El tiempo de restauración es solo el técnico: desde iniciar `restore` hasta que la base acepta
escrituras. No incluye detectar la falla, redirigir la aplicación ni validar.

## Cómo verificarlo

Desde esta carpeta:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

```bash
python3 -c '
import csv
p="medicion_archivado_20261101_083556"
it=list(csv.DictReader(open(p+"_intentos.csv")))
P={int(r["id"]) for r in it if r["etapa"]=="P"}; C={int(r["id"]) for r in it if r["etapa"]=="C"}
R={int(x) for x in open(p+"_ids_restaurados.txt").read().split()}
t={int(r["id"]):float(r["t_confirmacion_epoch"]) for r in csv.DictReader(open(p+"_confirmaciones.csv"))}
m={r["evento"]:float(r["t_epoch"]) for r in csv.DictReader(open(p+"_marcas.csv"))}
perd=sorted(C-R); rec=sorted(C&R)
print("confirmadas",len(C),"recuperadas",len(rec),"perdidas",len(perd),"indeterminadas",len(P-C),"anomalias",len(R-P))
print("perdidas entre %.2f y %.2f s antes de la detencion" % (m["kill"]-t[perd[0]], m["kill"]-t[perd[-1]]))
print("restauracion tecnica %.1f s" % (m["restauracion_disponible"]-m["restauracion_inicio"]))'
```

## Archivos

| Archivo | Contenido |
|---|---|
| `*_intentos.csv` | Registro externo: `escenario,id,etapa` (`P` intento, `C` COMMIT acusado). |
| `*_confirmaciones.csv` | Id, hora del servidor y LSN tras cada COMMIT. |
| `*_ids_restaurados.txt` | Ids presentes en la base restaurada. |
| `*_marcas.csv` | Inicio, detención (`kill`) y fases de la restauración. La hora de `kill` está corregida por el desfase entre relojes medido (+0,018 ± 0,054 s). |
| `*_evidencia_e.txt` | Inventario, montajes, huella del registro externo, tiempos y verificaciones. |
| `*_log_pgbackrest_restore.txt`, `*_log_restaurada.txt` | Logs de la restauración y del arranque de la instancia restaurada. |
| `medicion_archivado_20261101_083556.txt` | Salida completa de la ejecución. |
| `*_demo_antes.txt`, `*_demo_despues.txt` | Estado de la demo antes y después: idénticos. |

El script de medición está en una rama local separada (`medicion-archivado`). No forma parte de la
entrega oficial y no está publicado en este repositorio.

## Limitaciones

- **Una sola ejecución**, de 30 s de carga, en Docker Desktop.
- **Falla simulada con `docker kill`**: no reproduce la pérdida física del disco ni del equipo.
- **Repositorio local**: si se pierde el equipo, se pierden la base y los respaldos. En producción,
  el repositorio debe estar en otro servidor y otro lugar.
- **No es un RPO garantizado.** La pérdida depende de la carga y del estado del archivado. Con poca
  carga, el segmento en curso puede tardar hasta `archive_timeout` (60 s) en archivarse. Si el
  archivado falla, se pierde todo lo pendiente. Para un RPO cero se requiere replicación síncrona.
