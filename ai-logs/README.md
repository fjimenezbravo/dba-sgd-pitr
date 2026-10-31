# Registros de conversaciones con IA

La prueba exige incluir los registros **completos** de las conversaciones con IA.

| Archivo | Herramienta | Contenido |
|---|---|---|
| `claude-code_20261031_revision-y-correcciones.jsonl` | Claude Code | Revisión del repositorio contra el enunciado y corrección de: objetivo PITR por XID, cambios legítimos post-respaldo, validación contra foto previa y README. |

Los registros de Claude Code se guardan en `~/.claude/projects/<proyecto>/<sesion>.jsonl` (un evento JSON por línea).

Antes de publicar, revisar que no contengan credenciales (por ejemplo, el valor de `POSTGRES_PASSWORD` de `.env`).
