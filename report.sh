#!/usr/bin/env bash
# claude-readguard – Auswertung
# Zeigt zuerst alle Zugriffe ausserhalb des Projektordners, danach die eigenen
# Prompts aus der Claude-Code-History mit den zeitlich darauf folgenden
# Dateizugriffen. Die Zuordnung über Zeitstempel ist nur eine Näherung.

LOG="$HOME/.claude-readguard/reads.log"
HIST="$HOME/.claude/history.jsonl"

echo "==============================================="
echo " claude-readguard – Bericht"
echo "==============================================="
echo

echo "--- Zugriffe AUSSERHALB des Projektordners ---"
if [ -f "$LOG" ] && grep -F '[AUSSERHALB]' "$LOG"; then
    :
else
    echo "(keine)"
fi
echo

if [ ! -f "$LOG" ]; then
    echo "Noch keine Zugriffe protokolliert ($LOG fehlt)."
    exit 0
fi

nur_zugriffsliste() {
    echo "--- Alle protokollierten Zugriffe ---"
    cat "$LOG"
    exit 0
}

echo "--- Prompts und nachfolgende Zugriffe ---"
echo "Hinweis: Die Zuordnung erfolgt nur über Zeitstempel und ist eine"
echo "Näherung – parallele Sitzungen oder Zeitabweichungen verfälschen sie."
echo

if ! command -v jq >/dev/null 2>&1; then
    echo "(jq fehlt – zeige nur die Zugriffsliste)"
    nur_zugriffsliste
fi

if [ ! -f "$HIST" ]; then
    echo "(History-Datei $HIST fehlt – zeige nur die Zugriffsliste)"
    nur_zugriffsliste
fi

# Prompts als "epoch<TAB>text" einlesen; bei unerwartetem Format zurückfallen.
PROMPTS=$(jq -r 'select(type == "object" and .timestamp != null and .display != null)
                 | "\(.timestamp / 1000 | floor)\t\(.display | gsub("\n"; " "))"' \
          "$HIST" 2>/dev/null | sort -n) || PROMPTS=""
if [ -z "$PROMPTS" ]; then
    echo "(History-Format nicht lesbar – zeige nur die Zugriffsliste)"
    nur_zugriffsliste
fi

# Log-Zeilen als "epoch<TAB>zeile" aufbereiten.
LOGLINES=$(while IFS= read -r line; do
    stamp="${line:0:19}"
    epoch=$(date -d "$stamp" '+%s' 2>/dev/null) || continue
    printf '%s\t%s\n' "$epoch" "$line"
done < "$LOG")

# Für jeden Prompt: Zugriffe im Fenster bis zum nächsten Prompt ausgeben.
printf '%s\n' "$PROMPTS" | {
    prev_ts=""
    prev_text=""
    ausgeben() {
        [ -z "$prev_ts" ] && return
        echo ">> $(date -d "@$prev_ts" '+%Y-%m-%d %H:%M:%S') PROMPT: $prev_text"
        printf '%s\n' "$LOGLINES" | while IFS=$'\t' read -r epoch line; do
            [ -z "$epoch" ] && continue
            if [ "$epoch" -ge "$prev_ts" ] && { [ -z "$1" ] || [ "$epoch" -lt "$1" ]; }; then
                echo "     $line"
            fi
        done
        echo
    }
    while IFS=$'\t' read -r ts text; do
        [ -z "$ts" ] && continue
        ausgeben "$ts"
        prev_ts="$ts"
        prev_text="$text"
    done
    ausgeben ""
}
