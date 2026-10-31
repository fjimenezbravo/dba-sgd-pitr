# Cómo usé la IA en esta prueba

El enunciado pide usar IA y mostrar *"registros reales donde se ve a la persona guiando, cuestionando y verificando"*. Este documento resume cómo la usé. Cada punto se puede comprobar en el registro de esta carpeta.

## Herramienta y rol

**Herramienta:** Claude Code (modelo Claude Opus), sobre el repositorio local, en una sola sesión el 31 de octubre.

### 1. Desarrollo inicial (29 al 31 de octubre, antes de la sesión)

Desarrollé la versión inicial del laboratorio de recuperación PITR con PostgreSQL 17, Docker Compose y pgBackRest, incluyendo su configuración, scripts y estructura de ejecución, y la presentación v3, con apoyo de la documentación oficial de PostgreSQL.

Según mi declaración, este trabajo lo hice **sin usar IA**. Git respalda la autoría y las fechas (commits `3c6ecf6` del 29-oct y `0c502ea` del 31-oct a las 10:37, anterior a cualquier cambio de Claude Code), pero no registra qué herramientas se usaron: que fue sin IA es mi declaración, no algo que Git demuestre.

Archivos que siguen exactamente como los dejé: `Dockerfile`, `compose.demo.yaml`, `config/pgbackrest.conf`, `sql/`, `.env.example` y `entorno-inicial.txt`.

### 2. Modificaciones de Claude Code (31 de octubre)

Incorporé Claude Code para revisar la implementación contra el enunciado. A partir de esa revisión, y por instrucción mía, Claude Code escribió y modificó código y documentación:
- **Recuperación por XID** y foto previa al incidente: reescribió en gran parte `04_incidente.sh`, `06_restaurar_pitr.sh` y `simular_incidente.sql`, y reemplazó mi `03` por `03_cambios_legitimos.sh` (que conserva mi restore point como plan B).
- **Validaciones:** reescribió `08_validar_integridad.sh` para comparar contra la foto previa y agregó `pgbackrest check` a mi `05_registros_posteriores.sh`.
- **Ajustes menores** en mis scripts `02` y `07` (una línea cada uno) y en el orquestador `ejecutar_recuperacion.sh` (modo `--auto`, nombre del proyecto desde `.env`, colores); la estructura de etapas y el checklist son míos.
- **Monitor de la demostración:** creó `scripts/monitor.sh`.
- **Documentación y presentación:** reescribió el README, escribió los documentos de esta carpeta y actualizó mi presentación v3 hasta la v5.
- **Ejecución:** corrió las demostraciones de prueba y los commits.

Sobre la atribución que muestra GitHub: los commits de la sesión los ejecutó Claude Code en mi equipo, por eso el autor aparece con mi identidad de Git, y Claude Code agrega automáticamente la línea `Co-Authored-By: Claude`. Algunos de esos commits y sus publicaciones los hizo sin que yo pidiera publicar en ese mensaje, aunque el contenido de cada cambio respondía a mis instrucciones.

### 3. Mis decisiones, pruebas y verificaciones

- **Decidí** qué cambios aplicar y cuáles descartar (los ejemplos están más abajo). Algunas propuestas técnicas, como recuperar por XID, vinieron de Claude Code y las aprobé.
- **Cuestioné y revisé** los resultados: por qué la postulación 50, si la lámina 11 era correcta, si el guion debía publicarse, qué archivos sobraban.
- **Ejecuté por mi cuenta** al menos cuatro ensayos completos de la demostración y las verificaciones previas a la presentación.

El registro completo de la sesión está en esta carpeta. Los ensayos que ejecuté en mi propia terminal no aparecen en el registro; su evidencia quedó en los resultados archivados.

## Mis reglas de uso

1. **La IA propone, yo decido.** Las decisiones de alcance fueron mías. Dentro de las tareas que pedí, Claude Code aplicó algunos ajustes menores que no solicité de forma explícita (por ejemplo, corregir el shebang del orquestador y agregar el modo `--auto`); los revisé y quedaron registrados.
2. **Nada se da por bueno sin una corrida real.** Cada cambio de código se probó con la demo completa y se revisó la evidencia en `results/`. Los cambios de documentación y de la presentación se revisaron visualmente.
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

### El monitor de la demostración: decisiones por etapas
La idea de un monitor visual llegó de otra fuente. Antes de implementarlo, lo evalué paso a paso:
- **Shell en vez de web:** pregunté cuál convenía. Elegí shell: todo en la misma pantalla que la demo, menos piezas que pueden fallar en vivo y coherente con el resto del proyecto.
- **Datos reales, no adornos:** el monitor solo consulta PostgreSQL y los archivos de evidencia. No muestra cifras escritas a mano.
- **Errores encontrados al probarlo:** en la corrida completa, el monitor mostraba "CORRECTO" heredado de la corrida anterior antes del incidente, y la primera versión de la columna ANTES nunca mostraba la foto. Ambos se corrigieron antes de publicar.
- **No ocultar los errores:** propuse ocultar el contador de fallos de archivado porque llamaba la atención. La recomendación fue no esconderlo, sino mostrar el estado actual ("al día" o "FALLANDO"): ocultarlo contradiría mi propia respuesta sobre cómo vigilar los respaldos. Acepté ese criterio.
- **Separar PITR y reconciliación:** otra sugerencia externa. La acepté porque refuerza la pregunta 3: el PITR no puede traer lo escrito después del error.

## Lo que no delegué

- Las decisiones de alcance: qué construir, qué dejar fuera y qué documentar como límite.
- La elección de qué propuestas aplicar y cuáles descartar.
- La presentación ante el comité y las respuestas a sus preguntas, que doy con mis palabras.

## Qué contienen los registros

Los archivos `.jsonl` de esta carpeta son copias sin editar de la sesión de Claude Code del 31-oct: cada mensaje, cada comando ejecutado y su resultado, hasta el momento de su última copia.
