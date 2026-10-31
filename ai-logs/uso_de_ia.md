# Cómo usé la IA en esta prueba

El enunciado pide usar IA y mostrar *"registros reales donde se ve a la persona guiando, cuestionando y verificando"*. Este documento resume cómo la usé. Cada punto se puede comprobar en los registros completos de esta carpeta.

## Herramienta y rol

- **Herramienta:** Claude Code (modelo Claude Opus), sobre el repositorio local.
- **Rol de la IA:** revisar, proponer, escribir código a pedido y ejecutar pruebas.
- **Mi rol:** decidir el alcance, aceptar o rechazar propuestas, verificar resultados y presentar. Las decisiones de diseño y de qué entregar son mías.

## Mis reglas de uso

1. **La IA propone, yo decido.** Ninguna propuesta se aplicó sin que yo la pidiera explícitamente.
2. **Nada se da por bueno sin una corrida real.** Cada cambio se probó con la demo completa y se revisó la evidencia en `results/`.
3. **Probar también que la validación falla cuando debe.** Una validación que siempre dice "correcto" no prueba nada.
4. **No sobrecargar.** Con plazo y 30 minutos de presentación, prioricé lo que el comité evalúa por sobre agregar funcionalidades.

## Ejemplos concretos

### Revisión contra el enunciado, no a ciegas
Pedí revisar el código **contra el PDF de la prueba**, no una revisión genérica. Salieron cuatro brechas críticas:
- la recuperación apuntaba a un *restore point* creado antes del error, algo que en un incidente real no existe;
- no había cambios legítimos entre el respaldo y el error;
- la validación comparaba sin las columnas que el error dañaba, así que siempre coincidía;
- faltaban entregables (registros de IA y README completo).

Elegí corregir solo esas cuatro y dejé para después las mejoras menores.

### Verificación con pruebas en negativo
Tras cambiar la recuperación al número de transacción del error (XID), pedí comprobar el resultado de tres formas:

| Objetivo de recuperación | Resultado | Validación |
|---|---|---|
| XID del error | Postulación 50 aprobada | Correcta |
| Hora del error | Postulación 50 aprobada | Correcta |
| Punto marcado antes | Se pierde la aprobación | **Falla, como debe** |

La tercera fila muestra que la validación detecta una recuperación incorrecta, no solo que imprime "correcto".

### Una crítica externa, evaluada antes de aplicarla
Llevé a la sesión una lista de 5 mejoras propuestas por otra fuente y pedí una opinión antes de aplicarlas:
- **Acepté** esperar el archivado del WAL con `pgbackrest check`: había una carrera real entre el archivado y la recuperación.
- **Descarté** agregar validaciones que ya estaban cubiertas por la comparación contra la foto previa.
- **Postergué** los modos `--fresh` y `--verify`.

### Preguntar antes de seguir agregando
Antes de sumar más cambios, pregunté si la solución ya cumplía. La respuesta fue que sí, así que no agregué carga continua ni otras alternativas: más riesgo antes de presentar, sin más puntos frente al comité. Hacer el UPDATE a mano en la demo quedó como decisión de presentación, no de código.

### Corregir a la IA cuando entendió mal
Pregunté cómo lo resolverían otros postulantes y la IA lo interpretó como "muchas personas postulando al subsidio" (concurrencia). Aclaré que me refería a los otros candidatos y reorienté la conversación hacia cómo diferenciar la presentación.

## Lo que no delegué

- Las decisiones de alcance: qué construir, qué dejar fuera y qué documentar como límite.
- La elección de qué propuestas aplicar y cuáles descartar.
- La presentación ante el comité y las respuestas a sus preguntas. El guion (`presentation/guion_presentacion.md`) es una guía; las respuestas las doy con mis palabras.

## Qué contienen los registros

Los archivos `.jsonl` de esta carpeta son las conversaciones completas, sin editar: cada mensaje, cada comando ejecutado y su resultado.
