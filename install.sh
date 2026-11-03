#!/usr/bin/env bash
# claude-readguard – Installation
# Kopiert den Hook nach ~/.claude-readguard/, legt eine Beispiel-allowlist an
# und registriert den Hook in ~/.claude/settings.json (mit Backup).

set -eu

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.claude-readguard"
HOOK="$TARGET_DIR/readguard.sh"
SPERRHOOK="$TARGET_DIR/sperrliste-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

# jq wird sowohl hier als auch vom Hook selbst gebraucht.
if ! command -v jq >/dev/null 2>&1; then
    echo "FEHLER: jq ist nicht installiert. Bitte nachholen mit:"
    echo "    sudo apt install jq"
    exit 1
fi

mkdir -p "$TARGET_DIR"
# Hooks kopieren. Schreibgeschützte Ziele (chattr +i) mit gleichem Inhalt
# werden übersprungen; bei abweichendem Inhalt folgt ein Hinweis.
hook_kopieren() {  # hook_kopieren QUELLE ZIEL
    if [ -f "$2" ] && cmp -s "$1" "$2"; then
        echo "Unverändert: $2"
    elif cp "$1" "$2" 2>/dev/null && chmod +x "$2" 2>/dev/null; then
        echo "Hook installiert: $2"
    else
        echo "ACHTUNG: $2 konnte nicht ersetzt werden (schreibgeschützt?)."
        echo "         Schutz aufheben mit:  sudo chattr -i $2   und erneut installieren."
    fi
}
hook_kopieren "$SRC_DIR/readguard.sh" "$HOOK"
hook_kopieren "$SRC_DIR/sperrliste-hook.sh" "$SPERRHOOK"

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

# Beispiel-sperrliste nur anlegen, wenn noch keine existiert.
if [ ! -f "$TARGET_DIR/sperrliste" ]; then
    cp "$SRC_DIR/sperrliste.beispiel" "$TARGET_DIR/sperrliste"
    echo "Beispiel-sperrliste angelegt: $TARGET_DIR/sperrliste"
else
    echo "sperrliste existiert bereits, bleibt unverändert."
fi

# Berichts-Befehle und Startmenü-Eintrag anlegen.
mkdir -p "$HOME/.local/bin"
ln -sf "$SRC_DIR/report.sh" "$HOME/.local/bin/readguard-report"
ln -sf "$SRC_DIR/report-html.sh" "$HOME/.local/bin/readguard-html"
ln -sf "$SRC_DIR/claude-audit.sh" "$HOME/.local/bin/claude-audit"
ln -sf "$SRC_DIR/audit-report.sh" "$HOME/.local/bin/readguard-audit"
ln -sf "$SRC_DIR/readguard-app.py" "$HOME/.local/bin/readguard-app"
chmod +x "$SRC_DIR/report.sh" "$SRC_DIR/report-html.sh" \
         "$SRC_DIR/claude-audit.sh" "$SRC_DIR/audit-report.sh" "$SRC_DIR/readguard-app.py"
echo "Befehle angelegt: readguard-app, readguard-report, readguard-html, claude-audit, readguard-audit"
python3 -c 'import tkinter' 2>/dev/null \
    || echo "Hinweis: Für die Fenster-App fehlt noch Tkinter:  sudo apt install python3-tk"
command -v strace >/dev/null 2>&1 \
    || echo "Hinweis: Für claude-audit fehlt noch strace:  sudo apt install strace"

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/claude-readguard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Readguard
GenericName=Claude-Code-Zugriffsbericht
Comment=Zeigt, welche Dateien Claude Code gelesen hat
Exec=python3 $SRC_DIR/readguard-app.py
Icon=security-high
Terminal=false
Categories=Utility;Security;Monitor;
EOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Startmenü-Eintrag angelegt: Readguard"

# settings.json vorbereiten und sichern.
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi
BACKUP="$SETTINGS.bak.$(date '+%Y%m%d-%H%M%S')"
cp "$SETTINGS" "$BACKUP"
echo "Backup angelegt: $BACKUP"

# Hook eintragen, aber nur wenn er nicht schon drinsteht.
registrieren() {  # registrieren BEFEHL MATCHER STATUSTEXT
    local TMP; TMP="$(mktemp)"
    jq --arg cmd "$1" --arg m "$2" --arg s "$3" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        if ([.hooks.PreToolUse[]?.hooks[]?.command] | index($cmd)) then .
        else .hooks.PreToolUse += [{
            "matcher": $m,
            "hooks": [{"type": "command", "command": $cmd, "statusMessage": $s}]
        }]
        end
    ' "$SETTINGS" > "$TMP"
    mv "$TMP" "$SETTINGS"
    echo "Hook registriert: $1 (Matcher: $2)"
}
# Die Sperrliste zuerst: sie soll vor der Rückfrage greifen und auch bei
# schreibenden Werkzeugen gelten.
registrieren "$SPERRHOOK" "Read|Glob|Grep|Edit|Write|MultiEdit|Bash|NotebookRead|NotebookEdit|LSP" "Sperrliste prueft"
registrieren "$HOOK" "Read|Glob|Grep|Bash|NotebookRead" "Readguard prueft"
echo
echo "Fertig. Neue Claude-Code-Sitzungen verwenden den Hook automatisch;"
echo "eine bereits laufende Sitzung muss neu gestartet werden."
