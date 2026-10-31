# Registros de conversaciones con IA

La prueba exige incluir los registros **completos** de las conversaciones con IA. El resumen de cómo la usé está en [`uso_de_ia.md`](uso_de_ia.md). El trabajo previo, del 29 al 31 de octubre, se hizo sin IA, con la documentación oficial de PostgreSQL; por eso hay un solo registro.

| Archivo | Herramienta | Contenido |
|---|---|---|
| `uso_de_ia.md` | — | Resumen: reglas de uso, ejemplos de verificación y de crítica, qué no delegué. |
| `claude-code_20261031_revision-y-correcciones.jsonl` | Claude Code | Revisión contra el enunciado; recuperación por XID; validación contra foto previa; `pgbackrest check`; README; guion y presentación; monitor de la demostración. |

Los registros de Claude Code se guardan en `~/.claude/projects/<proyecto>/<sesion>.jsonl` (un evento JSON por línea).

Antes de publicar, revisar que no contengan credenciales (por ejemplo, el valor de `POSTGRES_PASSWORD` de `.env`).
