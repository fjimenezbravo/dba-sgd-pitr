-- Proyecto: Laboratorio DBA - PITR PostgreSQL
-- Proposito: Simular un UPDATE accidental sin WHERE.
-- ADVERTENCIA: modifica todos los registros de postulaciones.
-- Ejecutar solo en el entorno de prueba preparado.
--
-- Se registran el XID y la hora de la transaccion del incidente: son el
-- objetivo de la recuperacion PITR (se restaura justo antes de su COMMIT).

BEGIN;

SELECT 'XID_INCIDENTE=' || pg_current_xact_id();
SELECT 'HORA_INCIDENTE=' || clock_timestamp();

UPDATE postulaciones
SET estado = 'rechazada',
    observacion = 'INCIDENTE: UPDATE accidental sin WHERE';

SELECT 'AFECTADOS=' || COUNT(*) FILTER (
    WHERE estado = 'rechazada'
      AND observacion = 'INCIDENTE: UPDATE accidental sin WHERE'
)
FROM postulaciones;

COMMIT;
