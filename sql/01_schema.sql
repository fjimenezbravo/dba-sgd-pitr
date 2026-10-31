-- Proyecto: Recuperacion PITR con PostgreSQL 17 y pgBackRest
-- Proposito: Definir la tabla de postulaciones para la prueba tecnica.

CREATE TABLE IF NOT EXISTS postulaciones (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_postulante VARCHAR(100) NOT NULL,
    cargo VARCHAR(150) NOT NULL,
    region VARCHAR(50) NOT NULL,
    estado VARCHAR(30) NOT NULL DEFAULT 'en_revision',
    creado_en TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    observacion TEXT
);

COMMENT ON TABLE postulaciones IS
    'Tabla ficticia para demostrar respaldo, incidente y recuperacion PITR';
