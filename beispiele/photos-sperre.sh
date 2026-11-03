#!/usr/bin/env bash
# photos-sperre – PreToolUse-Hook für Claude Code (Thomas, 16.09.2026):
# „ich will Claude da komplett aussperren".
# Verweigert JEDEN Werkzeugaufruf, dessen Eingabe die Fotoordner nennt –
# egal ob Read, Grep, Glob, Edit, Write oder ein Bash-/SSH-Kommando.
# Ergänzt die deny-Regeln in ~/.claude/settings.json (die greifen nur
# bei den Datei-Werkzeugen, nicht bei Bash) und den readguard.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
EINGABE=$(printf '%s' "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
[ -z "$EINGABE" ] && exit 0

# Alle Schreibweisen der beiden Orte, lokal und auf der NAS (per ssh):
#   /mnt/NAS_shared/Photos   ~/Photos   $HOME/Photos   /home/thobug/Photos
#   /volume1/photo (derselbe Ordner, von der NAS aus gesehen)
MUSTER='NAS_shared/Photos|/home/thobug/Photos|~/Photos|\$HOME/Photos|\$\{HOME\}/Photos|/volume1/photo'

if printf '%s' "$EINGABE" | grep -qiE "$MUSTER"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [GESPERRT] $(printf '%s' "$INPUT" | jq -r '.tool_name // "?"') $(printf '%s' "$EINGABE" | cut -c1-200)" >> "$HOME/.claude-readguard/reads.log"
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Fotos sind fuer Claude gesperrt: ~/Photos und /mnt/NAS_shared/Photos (Thomas, 16.09.2026). Nicht umgehen, sondern Thomas fragen."}}'
fi
exit 0
