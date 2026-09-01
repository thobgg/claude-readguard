#!/usr/bin/env bash
# claude-readguard – HTML-Bericht
# Erzeugt aus reads.log eine lokale HTML-Datei (~/.claude-readguard/report.html)
# und öffnet sie im Browser. Rein lokal über file:// – kein Server, nichts
# verlässt den Rechner. Bewusst ohne Chat-Inhalte: Prompts erscheinen nirgends.
# Aufruf: report-html.sh [--no-open]

LOG="$HOME/.claude-readguard/reads.log"
OUT="$HOME/.claude-readguard/report.html"
MAX_BASH=30

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

STAND=$(date '+%d.%m.%Y %H:%M')

# Nur Zeilen mit Zeitstempel auswerten (mehrzeilige Altlasten ignorieren).
if [ -f "$LOG" ]; then
    grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} ' "$LOG" > "$TMPD/lines" || true
else
    : > "$TMPD/lines"
fi
grep -vF -e '[AUSSERHALB]' -e '[FEHLER]' "$TMPD/lines" > "$TMPD/acc" || true

# --- Kennzahlen -------------------------------------------------------------
TOTAL=$(wc -l < "$TMPD/acc")
OUTSIDE=$(grep -cF '[AUSSERHALB]' "$TMPD/lines" || true)
FIRST=$(head -n1 "$TMPD/lines" | cut -c1-16); FIRST=${FIRST:-–}
LAST=$(tail -n1 "$TMPD/lines" | cut -c1-16);  LAST=${LAST:-–}

# --- Zugriffe ausserhalb des Projektordners --------------------------------
OUTSIDE_ROWS=$(grep -F '[AUSSERHALB]' "$TMPD/lines" | tac | while IFS= read -r line; do
    ts="${line:0:16}"
    tool=$(printf '%s' "$line" | sed -n 's/.*\[AUSSERHALB\] \[\([^]]*\)\].*/\1/p')
    path=$(printf '%s' "$line" | sed 's/.*\[AUSSERHALB\] \[[^]]*\] //' | esc)
    printf '<tr><td class="time">%s</td><td><span class="tool">%s</span></td><td class="path">%s</td></tr>\n' \
        "$ts" "$tool" "$path"
done)
[ -z "$OUTSIDE_ROWS" ] && OUTSIDE_ROWS='<tr><td colspan="3" class="empty">Keine – alles blieb im Projektordner oder auf der Allowlist.</td></tr>'

# --- Ordner-Übersicht (ohne Bash-Kommandos) --------------------------------
FOLDER_ROWS=$(grep -v ' \[Bash\] ' "$TMPD/acc" \
    | sed 's/^.\{20\}\[[^]]*\] //' \
    | awk -F/ 'NF>4{print "/"$2"/"$3"/"$4"/…"; next}{print}' \
    | sort | uniq -c | sort -rn | head -12 \
    | while read -r n p; do
        printf '<tr><td class="path">%s</td><td class="num2">%s</td></tr>\n' "$(printf '%s' "$p" | esc)" "$n"
    done)
[ -z "$FOLDER_ROWS" ] && FOLDER_ROWS='<tr><td colspan="2" class="empty">Noch keine Zugriffe.</td></tr>'

# --- Ausgeführte Bash-Befehle ----------------------------------------------
BASH_ROWS=$(grep ' \[Bash\] ' "$TMPD/acc" | tail -n "$MAX_BASH" | tac | while IFS= read -r line; do
    ts="${line:0:16}"
    cmd=$(printf '%s' "$line" | sed 's/^.\{20\}\[Bash\] //' | cut -c1-160 | esc)
    printf '<tr><td class="time">%s</td><td class="path">%s</td></tr>\n' "$ts" "$cmd"
done)
[ -z "$BASH_ROWS" ] && BASH_ROWS='<tr><td colspan="2" class="empty">Keine.</td></tr>'

# --- Alle Zugriffe nach Tag -------------------------------------------------
DAY_HTML=""
for day in $(cut -c1-10 "$TMPD/acc" | sort -ur); do
    rows=$(grep "^$day " "$TMPD/acc" | while IFS= read -r line; do
        t="${line:11:5}"
        tool=$(printf '%s' "$line" | sed -n 's/^.\{20\}\[\([^]]*\)\].*/\1/p')
        path=$(printf '%s' "$line" | sed 's/^.\{20\}\[[^]]*\] //' | cut -c1-200 | esc)
        printf '<tr><td class="time">%s</td><td><span class="tool">%s</span></td><td class="path">%s</td></tr>\n' \
            "$t" "$tool" "$path"
    done)
    n=$(grep -c "^$day " "$TMPD/acc")
    DAY_HTML+="<details><summary>$day <span class=\"count\">$n Zugriffe</span></summary>
<table><thead><tr><th>Zeit</th><th>Tool</th><th>Pfad</th></tr></thead><tbody>
$rows</tbody></table></details>
"
done
[ -z "$DAY_HTML" ] && DAY_HTML='<p class="empty">Noch keine Zugriffe protokolliert.</p>'

# --- HTML schreiben ---------------------------------------------------------
cat > "$OUT" <<HTML
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>claude-readguard – Bericht</title>
<style>
:root{color-scheme:light dark;
  --bg:#f4f5f7;--surface:#ffffff;--ink:#1b1e24;--ink2:#5c6470;--line:#e2e5ea;
  --accent:#40589c;--warn-ink:#9c2f24;--warn-bg:#fbeeec;--chip:#eef0f4;}
@media (prefers-color-scheme:dark){:root{
  --bg:#15171c;--surface:#1e222a;--ink:#e7e9ec;--ink2:#98a1ac;--line:#2d333d;
  --accent:#93a7e8;--warn-ink:#f0a196;--warn-bg:#3b2521;--chip:#282e38;}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif;padding:32px 20px 60px}
main{max-width:960px;margin:0 auto}
h1{font-size:1.5rem;margin:0 0 4px}
.sub{color:var(--ink2);margin:0 0 28px}
h2{font-size:1.05rem;margin:36px 0 12px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px}
.tile{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:16px 18px}
.tile .num{font-size:1.9rem;font-weight:650;letter-spacing:-.02em}
.tile .lbl{color:var(--ink2);font-size:.85rem;margin-top:2px}
.tile.warn .num{color:var(--warn-ink)}
.card{background:var(--surface);border:1px solid var(--line);border-radius:10px;overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:.88rem}
th{text-align:left;color:var(--ink2);font-weight:600;padding:10px 14px;border-bottom:1px solid var(--line);white-space:nowrap}
td{padding:8px 14px;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:0}
.time{white-space:nowrap;color:var(--ink2);font-variant-numeric:tabular-nums}
.tool{background:var(--chip);border-radius:6px;padding:1px 8px;font-size:.8rem}
.path{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.82rem;word-break:break-all}
.num2{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.empty{color:var(--ink2);padding:14px}
details{background:var(--surface);border:1px solid var(--line);border-radius:10px;margin-bottom:10px;overflow-x:auto}
summary{cursor:pointer;padding:12px 16px;list-style-position:inside}
summary:hover{color:var(--accent)}
.count{color:var(--ink2);font-size:.82rem;white-space:nowrap}
.warnbox{background:var(--warn-bg);color:var(--warn-ink);border-radius:10px;padding:12px 16px;font-size:.88rem;margin-top:8px}
.note{color:var(--ink2);font-size:.85rem;margin-top:6px}
</style>
</head>
<body>
<main>
<h1>claude-readguard – Bericht</h1>
<p class="sub">Stand: $STAND · rein lokale Datei, kein Server · ohne Chat-Inhalte</p>

<div class="tiles">
  <div class="tile"><div class="num">$TOTAL</div><div class="lbl">protokollierte Zugriffe</div></div>
  <div class="tile warn"><div class="num">⚠ $OUTSIDE</div><div class="lbl">davon ausserhalb des Projektordners</div></div>
  <div class="tile"><div class="num" style="font-size:1.05rem;line-height:1.4">$FIRST&nbsp;bis<br>$LAST</div><div class="lbl">überwachter Zeitraum</div></div>
</div>

<h2>⚠ Zugriffe ausserhalb des Projektordners</h2>
<p class="note">Neueste zuerst. Diese Zugriffe haben in Claude Code eine Rückfrage ausgelöst (bzw. wurden bei Bash nur protokolliert).</p>
<div class="card">
<table><thead><tr><th>Zeit</th><th>Tool</th><th>Pfad</th></tr></thead><tbody>
$OUTSIDE_ROWS
</tbody></table>
</div>

<h2>Wo wurde gelesen? (Ordner-Übersicht)</h2>
<div class="card">
<table><thead><tr><th>Ordner</th><th class="num2">Zugriffe</th></tr></thead><tbody>
$FOLDER_ROWS
</tbody></table>
</div>

<h2>Ausgeführte Bash-Befehle</h2>
<p class="note">Achtung, blinder Fleck: Bei Bash sieht der Hook nur den Befehlstext – welche Dateien ein Befehl wirklich liest, steht dort nicht. Zum Nachschauen aufklappen.</p>
<details>
<summary>Die letzten $MAX_BASH Befehle anzeigen</summary>
<table><thead><tr><th>Zeit</th><th>Befehl</th></tr></thead><tbody>
$BASH_ROWS
</tbody></table>
</details>

<h2>Alle Zugriffe nach Tag</h2>
$DAY_HTML

<div class="warnbox"><strong>Datenschutz:</strong> Diese Datei enthält echte Pfad- und Projektnamen und gekürzte Bash-Kommandozeilen. Nicht weitergeben, nicht in ein Repository legen.</div>
</main>
</body>
</html>
HTML

echo "Bericht geschrieben: $OUT"
if [ "${1:-}" != "--no-open" ]; then
    xdg-open "$OUT" >/dev/null 2>&1 &
fi
