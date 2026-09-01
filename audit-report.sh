#!/usr/bin/env bash
# claude-readguard – Auswertung einer lückenlosen Aufzeichnung (strace)
# Aufruf: readguard-audit [strace-log]   – ohne Argument: neueste Aufzeichnung
#
# Zeigt jede tatsächlich geöffnete Datei, egal ob per Tool oder Bash-Befehl.
# System-Rauschen (Programmbibliotheken, /proc, Claude-eigene Dateien) wird
# herausgefiltert; die vollständigen Rohdaten bleiben im Log erhalten.

AUDITDIR="$HOME/.claude-readguard/audit"
RAW="${1:-$(ls -t "$AUDITDIR"/strace-*.log 2>/dev/null | head -n1)}"

if [ -z "$RAW" ] || [ ! -f "$RAW" ]; then
    echo "Keine Aufzeichnung gefunden. Erst eine Sitzung mit  claude-audit  starten."
    exit 1
fi

CWD=$(sed -n 's/^CWD //p' "$RAW.meta" 2>/dev/null | head -n1)

echo "==============================================="
echo " claude-readguard – lückenlose Auswertung"
echo "==============================================="
echo "Aufzeichnung: $RAW"
[ -n "$CWD" ] && echo "Projektordner: $CWD"
echo

# Pfade aus openat()/execve()-Zeilen ziehen.
ALLE=$(sed -n \
    -e 's/.*openat([^"]*"\([^"]*\)".*/\1/p' \
    -e 's/.*execve("\([^"]*\)".*/\1/p' \
    "$RAW" | sort | uniq -c | sort -rn)

# System- und Claude-Rauschen ausblenden – bewusst konservativ, damit echte
# Nutzerdaten (z. B. ~/.local/share/...) sichtbar bleiben.
ist_rauschen() {
    case "$1" in
        /usr/*|/lib*|/bin/*|/sbin/*|/etc/*|/proc/*|/sys/*|/dev/*|/run/*|/snap/*|/opt/*|/var/*) return 0 ;;
        "$HOME"/.claude*|"$HOME"/.npm*|"$HOME"/.cache/*|"$HOME"/.nvm/*|"$HOME"/.config/claude*) return 0 ;;
        /tmp/claude-*|/tmp/.X11*|/tmp/.ICE*|/memfd:*|pipe:*|socket:*|/dev/shm/*) return 0 ;;
        */node_modules/*) return 0 ;;
    esac
    return 1
}

INNEN=0; INNEN_LISTE=""; AUSSEN_LISTE=""
while read -r n p; do
    [ -z "$p" ] && continue
    ist_rauschen "$p" && continue
    if [ -n "$CWD" ] && case "$p" in "$CWD"|"$CWD"/*|[!/]*) true ;; *) false ;; esac; then
        INNEN=$((INNEN + n))
        INNEN_LISTE+=$(printf '%6s  %s' "$n" "$p")$'\n'
    else
        AUSSEN_LISTE+=$(printf '%6s  %s' "$n" "$p")$'\n'
    fi
done <<< "$ALLE"

echo "--- Geöffnete Dateien AUSSERHALB des Projektordners ---"
echo "(Anzahl Öffnungen, Pfad – System-Rauschen ausgeblendet)"
if [ -n "$AUSSEN_LISTE" ]; then printf '%s' "$AUSSEN_LISTE"; else echo "(keine)"; fi
echo

echo "--- Innerhalb des Projektordners ---"
if [ -n "$INNEN_LISTE" ]; then printf '%s' "$INNEN_LISTE"; else echo "(keine)"; fi
echo

echo "Hinweis: Diese Liste kommt vom Betriebssystem (strace), nicht von Claude"
echo "selbst – sie erfasst auch alles, was innerhalb von Bash-Befehlen geöffnet"
echo "wurde. Ausgeblendet wurden Programmbibliotheken und Claude-eigene Dateien;"
echo "die ungefilterten Rohdaten stehen in der Aufzeichnungsdatei."
