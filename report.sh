#!/usr/bin/env bash
# claude-readguard – Textbericht
# Zeigt die Zugriffe ausserhalb des Projektordners, eine Ordner-Übersicht und
# die vollständige Zugriffsliste. Bewusst ohne Chat-Inhalte: Prompts erscheinen
# nirgends – der Fokus liegt auf den Dateizugriffen.

LOG="$HOME/.claude-readguard/reads.log"

echo "==============================================="
echo " claude-readguard – Bericht"
echo "==============================================="
echo

if [ ! -f "$LOG" ]; then
    echo "Noch keine Zugriffe protokolliert ($LOG fehlt)."
    exit 0
fi

# Nur Zeilen mit Zeitstempel auswerten (mehrzeilige Altlasten ignorieren).
LINES=$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} ' "$LOG")

echo "--- Zugriffe AUSSERHALB des Projektordners ---"
printf '%s\n' "$LINES" | grep -F '[AUSSERHALB]' || echo "(keine)"
echo

echo "--- Ordner-Übersicht (ohne Bash-Befehle) ---"
printf '%s\n' "$LINES" \
    | grep -vF -e '[AUSSERHALB]' -e '[FEHLER]' \
    | grep -v ' \[Bash\] ' \
    | sed 's/^.\{20\}\[[^]]*\] //' \
    | awk -F/ 'NF>4{print "/"$2"/"$3"/"$4"/…"; next}{print}' \
    | sort | uniq -c | sort -rn | head -12
echo

echo "--- Alle protokollierten Zugriffe ---"
printf '%s\n' "$LINES" | grep -vF -e '[AUSSERHALB]' -e '[FEHLER]'
