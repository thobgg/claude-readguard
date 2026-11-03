#!/usr/bin/env bash
# sperrliste-hook – PreToolUse-Hook für Claude Code (16.09.2026).
# Liest ~/.claude-readguard/sperrliste (ein Muster je Zeile, # = Kommentar)
# und verweigert jede Werkzeugeingabe, die auf eines der Muster passt.
# Damit lassen sich weitere Sperren nachtragen, ohne Skripte anzufassen.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
LISTE="$HOME/.claude-readguard/sperrliste"
[ -f "$LISTE" ] || exit 0
EINGABE=$(printf '%s' "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
[ -z "$EINGABE" ] && exit 0

while IFS= read -r muster; do
    case "$muster" in ""|\#*) continue ;; esac
    if printf '%s' "$EINGABE" | grep -qiE -- "$muster"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [GESPERRT] $(printf '%s' "$INPUT" | jq -r '.tool_name // "?"') (sperrliste: $muster) $(printf '%s' "$EINGABE" | cut -c1-200)" >> "$HOME/.claude-readguard/reads.log"
        jq -n --arg m "$muster" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":("Gesperrt laut ~/.claude-readguard/sperrliste (Muster: " + $m + "). Nicht umgehen, sondern Thomas fragen.")}}'
        exit 0
    fi
done < "$LISTE"
exit 0
