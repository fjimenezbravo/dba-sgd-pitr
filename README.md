# Laboratorio DBA: recuperación PITR y reconciliación de datos

## 1. Objetivo

Demostrar un procedimiento de recuperación ante un UPDATE accidental que modifica registros de una base de datos PostgreSQL.

El laboratorio permite:

- Generar respaldos FULL mediante pgBackRest.
- Mantener archivado continuo de WAL.
- Definir un punto de recuperación anterior al incidente.
- Restaurar PostgreSQL 17 mediante Point-in-Time Recovery (PITR).
- Recuperar registros legítimos creados después del punto de recuperación.
- Validar la integridad de los datos originales y preservar los registros posteriores.

El escenario utiliza datos ficticios y se ejecuta localmente mediante Docker Compose.

## 2. Arquitectura

Se utilizan dos instancias PostgreSQL 17 independientes:

| Instancia | Puerto local | Función |
|---|---:|---|
| `postgres` | 5432 | Base de origen, que conserva el estado posterior al incidente |
| `recovery` | 5433 | Instancia restaurada mediante PITR y posteriormente reconciliada |

La instancia de recuperación utiliza un volumen de datos independiente y accede al repositorio de respaldos de pgBackRest.

La recuperación se realiza de manera aislada, sin sobrescribir ni reemplazar la instancia de origen.

## 3. Componentes

- PostgreSQL 17.
- pgBackRest para administración de respaldos y archivado de WAL.
- Point-in-Time Recovery (PITR).
- Docker y Docker Compose.
- Bash para automatizar las operaciones.
- SQL para la preparación, simulación y validación de datos.
- CSV para preservar y transferir los registros legítimos posteriores al incidente.

## 4. Escenario ejecutado

1. Se inicia PostgreSQL 17 y se crea la estructura de la tabla `postulaciones`.
2. Se cargan 100 registros ficticios.
3. Se configura y valida la stanza de pgBackRest.
4. Se ejecuta un respaldo FULL.
5. Se establece un punto de recuperación identificado mediante un restore point.
6. Se simula un UPDATE accidental sin cláusula WHERE, que afecta los 100 registros originales.
7. Se insertan tres registros legítimos después del incidente.
8. Se exportan esos tres registros a un archivo CSV.
9. Se restaura una instancia PostgreSQL independiente al punto anterior al UPDATE mediante pgBackRest.
10. Se verifica que la instancia recuperada contiene los 100 registros originales sin el cambio accidental.
11. Se importan los tres registros posteriores desde el CSV.
12. Se valida que la instancia recuperada contiene los 103 registros esperados y que los datos originales coinciden con los del escenario inicial.

La instancia principal permanece intacta durante el procedimiento de recuperación y validación.

## 5. Requisitos

- Docker Desktop.
- Docker Compose.
- Bash.
- Git.
- Puertos locales 5432 y 5433 disponibles.
- Espacio suficiente para las imágenes y volúmenes Docker.

## 6. Configuración inicial

Clonar o descargar el repositorio y acceder a su directorio:

```bash
cd dba-sgd-pitr
```

## 7. Verificación del estado del clúster después de PITR

Una vez finalizada la recuperación Point-in-Time Recovery (PITR), se verificó el estado interno del clúster PostgreSQL recuperado mediante la herramienta `pg_controldata`.

Esta comprobación permite revisar información de control del clúster, incluyendo su estado y la línea de tiempo asociada al último checkpoint.

### Comando ejecutado

```bash
docker exec -u postgres dba-sgd-pitr-demo-recovery-1 \
  pg_controldata /var/lib/postgresql/data \
  | grep -E "Database cluster state|TimeLineID"
```
### Interpretación de los resultados

- **Database cluster state: in production:** indica que el clúster se encuentra operativo y fuera del estado de recuperación.
- **TimeLineID: 2:** identifica la línea de tiempo asociada al último checkpoint del clúster recuperado.
- **PrevTimeLineID: 2:** indica que la línea de tiempo anterior registrada en ese checkpoint también corresponde a la número 2.

### Conclusión

La comprobación confirma que el clúster recuperado se encuentra operativo y que su información de control registra la línea de tiempo 2.

Esta evidencia complementa las validaciones funcionales realizadas: conexión a PostgreSQL, recuperación de los 100 registros originales, reconciliación de los 3 registros posteriores al incidente y comparación de integridad de los datos.

La verificación mediante `pg_controldata` no sustituye las pruebas de integridad de los registros; ambas comprobaciones son complementarias.
