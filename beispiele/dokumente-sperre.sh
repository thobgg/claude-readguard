#!/usr/bin/env bash
# dokumente-sperre – PreToolUse-Hook für Claude Code (Thomas, 16.09.2026):
# ~/Dokumente ist gesperrt, mit EINER Ausnahme: ~/Dokumente/Ahnenforschung.
# Eine deny-Regel kann das nicht, weil deny in Claude Code immer über
# allow gewinnt – darum dieser Hook. Er prüft jede Werkzeugeingabe
# (Pfadfelder wie Bash-Kommandos) auf Nennungen von ~/Dokumente und
# verweigert, sobald eine davon NICHT unter Ahnenforschung liegt.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
EINGABE=$(printf '%s' "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
[ -z "$EINGABE" ] && exit 0

# Alle Schreibweisen des Ordners samt dem, was dahinter folgt.
DOK='(/home/thobug|~|\$HOME|\$\{HOME\})/Dokumente(/[^[:space:]"'"'"'`;|&)]*)?'
NENNUNGEN=$(printf '%s' "$EINGABE" | grep -oE "$DOK")
[ -z "$NENNUNGEN" ] && exit 0

# Erlaubt ist nur, was sauber unter Ahnenforschung liegt (kein ".." darin).
VERBOTEN=$(printf '%s\n' "$NENNUNGEN" | grep -vE '/Dokumente/Ahnenforschung(/|$)' ; printf '%s\n' "$NENNUNGEN" | grep -E '/\.\.(/|$)')

if [ -n "$VERBOTEN" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [GESPERRT] $(printf '%s' "$INPUT" | jq -r '.tool_name // "?"') $(printf '%s' "$EINGABE" | cut -c1-200)" >> "$HOME/.claude-readguard/reads.log"
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"~/Dokumente ist fuer Claude gesperrt; offen ist nur ~/Dokumente/Ahnenforschung (Thomas, 16.09.2026). Nicht umgehen, sondern Thomas fragen."}}'
fi
exit 0
