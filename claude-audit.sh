#!/usr/bin/env bash
# claude-readguard – lückenlose Aufzeichnung
# Startet Claude Code unter strace: JEDE Dateiöffnung von Claude Code und
# allen Unterprozessen wird auf Betriebssystemebene aufgezeichnet – auch
# Zugriffe innerhalb von Bash-Befehlen, die der Hook nicht sehen kann.
# Nach dem Beenden der Sitzung wird die Auswertung automatisch angezeigt.
#
# Aufruf: claude-audit [beliebige claude-Argumente]

AUDITDIR="$HOME/.claude-readguard/audit"
mkdir -p "$AUDITDIR"

if ! command -v strace >/dev/null 2>&1; then
    echo "FEHLER: strace ist nicht installiert. Bitte nachholen mit:"
    echo "    sudo apt install strace"
    exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
    echo "FEHLER: claude wurde nicht gefunden."
    exit 1
fi

STAMP=$(date '+%Y%m%d-%H%M%S')
RAW="$AUDITDIR/strace-$STAMP.log"
printf 'CWD %s\n' "$PWD" > "$RAW.meta"

echo "claude-readguard: lückenlose Aufzeichnung aktiv."
echo "Rohdaten: $RAW"
echo "Claude Code startet jetzt – nach dem Beenden folgt die Auswertung."
echo

strace -f -qq -e signal=none -e trace=openat,open,execve -e status=successful \
    -o "$RAW" claude "$@"
CODE=$?

echo
echo "Sitzung beendet – Auswertung:"
echo
SELF_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
bash "$SELF_DIR/audit-report.sh" "$RAW"
exit $CODE
