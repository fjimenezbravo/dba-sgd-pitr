-- Proyecto: Laboratorio DBA - PITR PostgreSQL
-- Proposito: Simular un UPDATE accidental sin WHERE.
-- ADVERTENCIA: modifica todos los registros de postulaciones.
-- Ejecutar solo en el entorno de prueba preparado.

BEGIN;

UPDATE postulaciones
SET estado = 'rechazada',
    observacion = 'INCIDENTE: UPDATE accidental sin WHERE';

-- Verificar el resultado antes de confirmar los cambios.
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (
        WHERE estado = 'rechazada'
          AND observacion = 'INCIDENTE: UPDATE accidental sin WHERE'
    ) AS afectados
FROM postulaciones;

COMMIT;
