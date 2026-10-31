# Volver al minuto anterior: PITR con PostgreSQL 17 y pgBackRest

Prueba técnica DBA – Secretaría de Gobierno Digital (programa ficticio *Conecta Rural*).

Un operador ejecuta un `UPDATE` sin `WHERE` que deja todas las postulaciones como `rechazada`. Con un `pg_dump` semanal, recuperar tomó días y se perdió trabajo. Este laboratorio muestra cómo volver la base **al instante exacto anterior al error** usando archivado continuo de WAL y recuperación a un punto en el tiempo (PITR) con pgBackRest, y cómo rescatar lo que se escribió después del incidente.

## 1. Cómo levantar y repetir la demostración

Requisitos: Docker Desktop (con Compose v2), Bash y los puertos 5432 y 5433 libres.

```bash
cp .env.example .env        # y definir POSTGRES_PASSWORD
```

```bash
./ejecutar_recuperacion.sh          # demo en vivo: pausa en cada etapa
```

```bash
./ejecutar_recuperacion.sh --auto   # sin pausas (grabación de respaldo)
```

El script borra el laboratorio anterior (`docker compose down --volumes` del proyecto `dba-sgd-pitr-demo`), construye la imagen y ejecuta las 7 etapas. Cada etapa deja su evidencia en `results/`.

Para recuperar con otro objetivo: `TARGET_TYPE=time` (hora del incidente) o `TARGET_TYPE=name` (restore point preventivo, plan B) antes de `bash scripts/06_restaurar_pitr.sh`. Antes hay que eliminar el contenedor `recovery` y su volumen.

## 2. Arquitectura

| Componente | Detalle |
|---|---|
| `postgres` (puerto 5432) | Base de producción simulada. `wal_level=replica`, `archive_mode=on`, `archive_command=pgbackrest archive-push`, `archive_timeout=60s`. |
| `pgbackrest_repo` (volumen) | Repositorio de pgBackRest: respaldos FULL y WAL archivado. Retención: 2 FULL. |
| `recovery` (puerto 5433) | Instancia independiente donde se restaura el PITR. Monta el repositorio en solo lectura. |

La recuperación se hace **en paralelo, sin tocar la base dañada**. Así se conserva la evidencia y lo escrito después del incidente, que luego se reincorpora.

```
 respaldo FULL ─► cambios legítimos ─► último cambio (id 50) ─► UPDATE sin WHERE ─► 3 postulaciones nuevas
      │                  (WAL)                (WAL)                   ▲ XID 746            (rescate por CSV)
      └──────────── restore + replay de WAL hasta justo antes del COMMIT ┘
```

## 3. Etapas

| # | Script | Qué hace |
|---|---|---|
| 0 | `sql/01_schema.sql`, `sql/02_datos_iniciales.sql` | Crea `postulaciones` con 100 registros ficticios al iniciar el contenedor. |
| 1 | `02_backup.sh` | Crea la stanza y un respaldo FULL; muestra `pgbackrest info`. |
| 2 | `03_cambios_legitimos.sh` | Revisores aprueban o preseleccionan 15 postulaciones **después del respaldo**: estos cambios solo vuelven si se reproduce el WAL. También crea un restore point preventivo (plan B). |
| 3 | `04_incidente.sh` | Último cambio legítimo (id 50), **foto previa** de todas las columnas, y 2 s después el `UPDATE` sin `WHERE`. Registra el **XID** y la **hora del servidor** de la transacción. |
| 4 | `05_registros_posteriores.sh` | Llegan 3 postulaciones nuevas y se exportan a CSV. `pg_switch_wal()` cierra el segmento del incidente y `pgbackrest check` **espera** a que esté en el repositorio (o falla), para que la recuperación no empiece antes de que llegue el WAL. |
| 5 | `06_restaurar_pitr.sh` | `pgbackrest restore --type=xid --target=<XID> --target-exclusive`: recupera hasta justo antes del `COMMIT` del incidente. Mide el RTO hasta que la base está promovida (`pg_is_in_recovery() = f`). |
| 6 | `07_reconciliar_post_incidente.sh` | Reincorpora las 3 postulaciones posteriores en la base recuperada. |
| 7 | `08_validar_integridad.sh` | Compara **todas las columnas** de los 100 registros recuperados contra la foto previa al `UPDATE` (diff + MD5). |

**Cómo se prueba que la recuperación queda "justo antes, ni antes ni después":**
- **No después:** ninguna fila queda `rechazada` por el incidente.
- **No antes:** el cambio a id 50, hecho 2 s antes del `UPDATE`, sí vuelve.

Prueba en negativo: recuperar con el restore point (`TARGET_TYPE=name`) pierde ese cambio, y la etapa 7 lo detecta y falla.

## 4. Resultados medidos

Corrida de referencia: `results/corrida_completa_20261031_113535.txt`.

En esa corrida, `pg_stat_archiver` muestra `failed_count = 2` sobre el primer segmento: PostgreSQL intentó archivar antes de que la etapa 1 creara la stanza. pgBackRest reintentó y el archivado se completó (`pgbackrest check` correcto). En producción la stanza se crea antes de activar `archive_mode`.

| Medida | Valor |
|---|---|
| Tamaño de la base / respaldo FULL en repo (comprimido) | 29,3 MB / 3,8 MB |
| Duración del respaldo FULL | 1,8 s |
| `pgbackrest restore` (copia de archivos) | 0,76 s |
| RTO técnico (inicio de restore → base promovida y escribible) | 2–3 s |
| Registros originales idénticos a la foto previa (7 columnas) | 100 / 100 (MD5 igual) |
| Registros posteriores rescatados | 3 / 3 → total 103, 0 rechazados |

## 5. Respuestas a las preguntas

**1. Si se pierde el disco de la base, ¿cuántos datos se pierden (RPO)?**
Se pierde lo que estaba en el WAL **aún no archivado**. Un segmento se archiva cuando se llena (16 MB) o, como máximo, cada `archive_timeout` = **60 s**. Con poca carga, el RPO es como máximo 60 s; con mucha carga, el segmento se llena antes y el RPO baja.

Depende de:
- `archive_timeout`;
- que `archive-push` funcione (si falla, el WAL se acumula sin respaldar y el RPO crece);
- **que el repositorio no esté en el mismo disco** (ver pregunta 4).

Para un RPO ≈ 0 haría falta replicación en streaming o `pg_receivewal` hacia otro servidor.

Frente a un error lógico como este `UPDATE`, la pérdida es **cero**: se vuelve al instante anterior y lo posterior se rescata.

**2. ¿Cuánto tarda en volver a estar disponible (RTO)? ¿Cómo crece?**
Medido: 2–3 s para 29 MB. El tiempo crece con:
- **el tamaño de la base**: la copia de archivos es aproximadamente lineal. Se acelera con `process-max`, discos rápidos y un repositorio cercano;
- **el WAL acumulado desde el último FULL**: se reproduce uno por uno. Respaldos más frecuentes (diferenciales o incrementales diarios) acotan este término.

No medí bases grandes; el siguiente paso sería repetir con `pgbench -i -s 1000` (unos 15 GB).

El RTO real también incluye **detectar** el incidente, decidir el punto y cambiar la aplicación a la base recuperada. Eso es tiempo humano y no está en los 3 s.

**3. ¿Qué pasó con lo escrito después del incidente?**
Las 3 postulaciones que llegaron después se exportan a CSV desde la base dañada y se reincorporan en la base recuperada.

Limitaciones (decisión consciente):
- En la demo se identifican con una marca (`observacion`). En la realidad se identificarían por `creado_en > hora del incidente` o por `id > max(id)` de la base recuperada.
- Solo se rescatan **inserciones**. Si después del incidente un revisor modificó una fila existente, ese cambio no se puede distinguir del daño (todas las filas fueron sobrescritas) y requiere revisión manual o una tabla de auditoría.
- Los `id` se reasignan al importar.

**4. ¿Dónde deben vivir los respaldos?**
**Fuera del servidor y del disco de la base.** En este laboratorio el repositorio es un volumen Docker en el mismo equipo: sirve para errores lógicos, pero si se pierde el equipo se pierden la base **y** los respaldos, y el RPO pasa a ser "todo". En producción:
- `repo1` en otro servidor o en almacenamiento de objetos dentro de la institución;
- un `repo2` en otra ubicación física;
- cifrado (`repo-cipher-type`);
- permisos que impidan que la cuenta de la base borre respaldos.

**5. ¿Cómo sabría, un martes cualquiera, que los respaldos sirven?**
Un respaldo que no se ha restaurado no está probado. Propongo:
- **Diario:** `pgbackrest check` (archiva un WAL de prueba) y `pgbackrest verify` (valida checksums del repositorio).
- **Alertas** si `pg_stat_archiver.failed_count` sube o si el último respaldo tiene más de 24 h.
- **Semanal, automatizado:** las etapas 5 y 7 de este repositorio (restaurar en un servidor aparte y validar contra conteos o checksums conocidos), registrando el RTO obtenido.

## 6. Supuestos y decisiones

- **Objetivo de recuperación por XID:** es exacto a nivel de transacción. El XID se obtiene en la demo al ejecutar el `UPDATE`. En un incidente real se busca con `pg_waldump` sobre el WAL archivado o se usa la hora aproximada (`--type=time`, también soportado). El restore point queda como plan B y la demo muestra su costo (pierde lo ocurrido entre el punto y el error).
- **Recuperación en instancia paralela, no en el lugar:** permite comparar y rescatar. El cambio de la aplicación a la base recuperada (promoverla como producción y reactivar su archivado, hoy `archive_mode=off`) queda fuera de alcance.
- **Solo respaldos FULL** y un único servidor; sin diferenciales, incrementales ni repositorio remoto.
- La validación usa una foto tomada por el script justo antes del incidente; en la realidad se contrastaría con conteos o reportes del negocio.

## 7. Límites (lo que esta solución no cubre)

- Pérdida del equipo completo, porque el repositorio está en el mismo host.
- Alta disponibilidad, réplicas y conmutación automática.
- Cifrado, retención por política y monitoreo con alertas.
- Rescate automático de modificaciones a filas existentes posteriores al incidente.

## 8. Uso de IA y material de presentación

- **IA:** cómo la usé, qué verifiqué y qué no delegué, en [`ai-logs/uso_de_ia.md`](ai-logs/uso_de_ia.md). Los registros completos están en `ai-logs/`.
- **Presentación:** [`presentation/Volver_al_minuto_anterior_v4.pptx`](presentation/Volver_al_minuto_anterior_v4.pptx) (17 láminas, con notas del orador) y el guion minuto a minuto con preguntas probables en [`presentation/guion_presentacion.md`](presentation/guion_presentacion.md).

## 9. Estado del clúster después del PITR

```bash
docker exec -u postgres dba-sgd-pitr-demo-recovery-1 \
  pg_controldata /var/lib/postgresql/data | grep -E "Database cluster state|TimeLineID"
```

`in production` y `TimeLineID: 2`: la base recuperada fue promovida y abrió una nueva línea de tiempo, separada de la historia original (línea 1). Esto evita que su WAL se confunda con el de la base dañada.
