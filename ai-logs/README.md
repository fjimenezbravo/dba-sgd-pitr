# Registros de conversaciones con IA

La prueba exige incluir los registros **completos** de las conversaciones con IA. El resumen de cómo la usé está en [`uso_de_ia.md`](uso_de_ia.md), que distingue mi desarrollo inicial, los cambios que hizo Claude Code el 31 de octubre y mis decisiones y pruebas.

Hay un solo registro porque, según mi declaración, la IA se usó solo en la sesión del 31 de octubre: el desarrollo inicial (del 29 al 31 de octubre, antes de esa sesión) lo hice sin IA, con la documentación oficial de PostgreSQL; Git registra la autoría y las fechas de los commits, pero no las herramientas usadas.

| Archivo | Herramienta | Contenido |
|---|---|---|
| `uso_de_ia.md` | — | Resumen: reglas de uso, ejemplos de verificación y de crítica, qué no delegué. |
| `claude-code_20261031_revision-y-correcciones.jsonl` | Claude Code | Revisión contra el enunciado; recuperación por XID; validación contra foto previa; `pgbackrest check`; README; guion y presentación; monitor de la demostración; auditorías y correcciones; colores del orquestador. |

Los registros de Claude Code se guardan en `~/.claude/projects/<proyecto>/<sesion>.jsonl` (un evento JSON por línea).

Antes de publicar, revisar que no contengan credenciales (por ejemplo, el valor de `POSTGRES_PASSWORD` de `.env`).
