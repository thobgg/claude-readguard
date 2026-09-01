#!/usr/bin/env bash
# claude-readguard – PreToolUse-Hook für Claude Code
# Protokolliert Dateizugriffe und fragt nach, bevor ausserhalb des
# Projektordners gelesen wird. Endet immer mit exit 0.

LOGDIR="$HOME/.claude-readguard"
LOG="$LOGDIR/reads.log"
ALLOWLIST="$LOGDIR/allowlist"

mkdir -p "$LOGDIR" 2>/dev/null

INPUT=$(cat)
TS=$(date '+%Y-%m-%d %H:%M:%S')

# Ohne jq können wir das Hook-JSON nicht auswerten: Fehler loggen, durchlassen.
if ! command -v jq >/dev/null 2>&1; then
    echo "$TS [FEHLER] jq nicht installiert - Zugriff ungeprueft durchgelassen" >> "$LOG"
    exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // .tool_input.command // empty' 2>/dev/null)

# Kein Zielpfad ermittelbar (z. B. Glob ohne path-Angabe): durchlassen.
[ -z "$TARGET" ] && exit 0

# Führendes ~ auflösen.
case "$TARGET" in
    "~/"*) TARGET="$HOME/${TARGET#\~/}" ;;
    "~")   TARGET="$HOME" ;;
esac

# Rauschen: liest Claude Code bei jedem Start selbst - weder loggen noch fragen.
case "$TARGET" in
    *.claude/*|*.claude.json*|*.npm/*|*.cache/claude*|*node_modules/*|*.config/claude*)
        exit 0 ;;
esac

# Jeden verbleibenden Zugriff protokollieren.
echo "$TS [$TOOL] $TARGET" >> "$LOG"

# Bash: nur protokollieren, nicht blockieren - im Kommandotext steht nicht,
# welche Dateien tatsächlich gelesen werden.
[ "$TOOL" = "Bash" ] && exit 0

# Relative Pfade beziehen sich auf das Projekt: durchlassen.
case "$TARGET" in
    /*) : ;;
    *)  exit 0 ;;
esac

# Innerhalb des Projektordners (.cwd): durchlassen.
if [ -n "$CWD" ]; then
    case "$TARGET" in
        "$CWD"|"$CWD"/*) exit 0 ;;
    esac
fi

# Allowlist: ein Muster pro Zeile, # = Kommentar, Wildcards erlaubt.
if [ -f "$ALLOWLIST" ]; then
    while IFS= read -r pattern; do
        case "$pattern" in ""|\#*) continue ;; esac
        case "$pattern" in
            "~/"*) pattern="$HOME/${pattern#\~/}" ;;
        esac
        # shellcheck disable=SC2254  # Wildcards im Muster sind gewollt
        case "$TARGET" in
            $pattern) exit 0 ;;
        esac
    done < "$ALLOWLIST"
fi

# Ausserhalb des Projekts und nicht freigegeben: zusätzlich markieren
# und Rückfrage bei Claude Code auslösen.
echo "$TS [AUSSERHALB] [$TOOL] $TARGET" >> "$LOG"
jq -n --arg reason "claude-readguard: Zugriff ausserhalb des Projektordners: $TARGET" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":$reason}}'
exit 0
