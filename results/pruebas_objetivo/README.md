# Pruebas de los tres objetivos de recuperación

Respaldan la lámina 11 de la presentación: *"Cómo sé que quedó justo antes: la postulación 50"*.

La postulación 50 se aprueba 2 segundos antes del UPDATE sin WHERE. Su estado después de recuperar muestra dónde quedó la base:
- `preseleccionada`: la recuperación quedó antes de tiempo;
- `aprobada`: quedó justo antes del error;
- `rechazada`: quedó después.

| Objetivo | Postulación 50 | Validación (`08_validar_integridad.sh`) | Evidencia |
|---|---|---|---|
| XID 746, exclusivo (por defecto) | aprobada | Correcta | Corrida de referencia en `results/` (11:35) |
| Hora del error (`TARGET_TYPE=time`) | aprobada | Correcta | `hora_*.txt` |
| Restore point (`TARGET_TYPE=name`) | preseleccionada | **Falla, como corresponde** | `punto_*.txt` |

La última fila es una prueba en negativo: demuestra que la validación detecta una recuperación incorrecta y no solo imprime "correcto".

**Origen:** estas pruebas se ejecutaron sobre la corrida de las **11:10 del 31-oct-2026**, que tiene el mismo código, los mismos datos y el mismo XID 746 que la corrida de referencia de las 11:35. El resto de los archivos de la corrida de las 11:10 está archivado en `legacy/` (no se publica).

**Recuperar por hora** funcionó porque la demo registra la hora exacta del servidor. En un incidente real la hora suele ser aproximada; por eso el objetivo por defecto es el XID.

## Cómo repetirlas

Después de `./ejecutar_recuperacion.sh`:

```bash
docker compose -p dba-sgd-pitr-demo -f compose.demo.yaml rm -sf recovery
```

```bash
docker volume rm dba-sgd-pitr-demo_pitrdata
```

```bash
TARGET_TYPE=time bash scripts/06_restaurar_pitr.sh && bash scripts/08_validar_integridad.sh
```

Para la prueba en negativo, se repiten los dos primeros comandos y se usa `TARGET_TYPE=name`; el script 08 debe terminar con error.
