-- Proyecto: Recuperacion PITR con PostgreSQL 17 y pgBackRest
-- Proposito: Crear datos ficticios reproducibles para la prueba.
-- No se utilizan datos personales reales.

INSERT INTO postulaciones (
    nombre_postulante,
    cargo,
    region,
    estado,
    creado_en,
    observacion
)
SELECT
    (ARRAY[
        'Ana Perez', 'Luis Gonzalez', 'Maria Soto', 'Pedro Rojas',
        'Carolina Diaz', 'Diego Munoz', 'Camila Silva', 'Felipe Torres',
        'Andrea Morales', 'Javier Contreras'
    ])[((n - 1) % 10) + 1],
    (ARRAY[
        'Administrador de Bases de Datos',
        'Administrador de Sistemas',
        'Analista de Datos',
        'Ingeniero de Infraestructura'
    ])[((n - 1) % 4) + 1],
    (ARRAY[
        'Metropolitana', 'Valparaiso', 'Biobio', 'Araucania',
        'Los Lagos'
    ])[((n - 1) % 5) + 1],
    (ARRAY[
        'en_revision', 'preseleccionada', 'pendiente'
    ])[((n - 1) % 3) + 1],
    TIMESTAMPTZ '2026-10-20 09:00:00+00'
        + ((n - 1) * INTERVAL '10 minutes'),
    'Registro ficticio de prueba ' || n
FROM generate_series(1, 100) AS serie(n);
