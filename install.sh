#!/usr/bin/env bash
# claude-readguard – Installation
# Kopiert den Hook nach ~/.claude-readguard/, legt eine Beispiel-allowlist an
# und registriert den Hook in ~/.claude/settings.json (mit Backup).

set -eu

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.claude-readguard"
HOOK="$TARGET_DIR/readguard.sh"
SETTINGS="$HOME/.claude/settings.json"

# jq wird sowohl hier als auch vom Hook selbst gebraucht.
if ! command -v jq >/dev/null 2>&1; then
    echo "FEHLER: jq ist nicht installiert. Bitte nachholen mit:"
    echo "    sudo apt install jq"
    exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$SRC_DIR/readguard.sh" "$HOOK"
chmod +x "$HOOK"
echo "Hook installiert: $HOOK"

# Beispiel-allowlist nur anlegen, wenn noch keine existiert.
if [ ! -f "$TARGET_DIR/allowlist" ]; then
    cat > "$TARGET_DIR/allowlist" <<'EOF'
# claude-readguard allowlist
# Ein Muster pro Zeile. Zeilen mit # sind Kommentare.
# Pfade, die hier stehen, werden geloggt, lösen aber keine Rückfrage aus.
# Wildcards sind erlaubt, führendes ~ wird zu deinem Home-Verzeichnis.
#
# Beispiele:
# ~/.gitconfig
# ~/Dokumente/oeffentlich/*
EOF
    echo "Beispiel-allowlist angelegt: $TARGET_DIR/allowlist"
else
    echo "allowlist existiert bereits, bleibt unverändert."
fi

# settings.json vorbereiten und sichern.
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi
BACKUP="$SETTINGS.bak.$(date '+%Y%m%d-%H%M%S')"
cp "$SETTINGS" "$BACKUP"
echo "Backup angelegt: $BACKUP"

# Hook eintragen, aber nur wenn er nicht schon drinsteht.
TMP="$(mktemp)"
jq --arg cmd "$HOOK" '
    .hooks //= {} |
    .hooks.PreToolUse //= [] |
    if ([.hooks.PreToolUse[]?.hooks[]?.command] | index($cmd)) then .
    else .hooks.PreToolUse += [{
        "matcher": "Read|Glob|Grep|Bash|NotebookRead",
        "hooks": [{"type": "command", "command": $cmd}]
    }]
    end
' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"
echo "Hook in $SETTINGS registriert (Matcher: Read|Glob|Grep|Bash|NotebookRead)."
echo
echo "Fertig. Neue Claude-Code-Sitzungen verwenden den Hook automatisch;"
echo "eine bereits laufende Sitzung muss neu gestartet werden."
