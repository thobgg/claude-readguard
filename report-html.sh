#!/usr/bin/env bash
# claude-readguard – HTML-Bericht
# Erzeugt aus reads.log und history.jsonl eine lokale HTML-Datei
# (~/.claude-readguard/report.html) und öffnet sie im Browser.
# Rein lokal über file:// – es läuft kein Server, es verlässt nichts den Rechner.
# Aufruf: report-html.sh [--no-open]

LOG="$HOME/.claude-readguard/reads.log"
HIST="$HOME/.claude/history.jsonl"
OUT="$HOME/.claude-readguard/report.html"
MAX_PROMPTS=30

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

STAND=$(date '+%d.%m.%Y %H:%M')

# --- Kennzahlen -------------------------------------------------------------
TOTAL=0; OUTSIDE=0; FIRST="–"; LAST="–"
if [ -f "$LOG" ]; then
    TOTAL=$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" 2>/dev/null | grep -cv -e '\[AUSSERHALB\]' -e '\[FEHLER\]' || echo 0)
    OUTSIDE=$(grep -cF '[AUSSERHALB]' "$LOG" 2>/dev/null || echo 0)
    FIRST=$(grep -E -m1 '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" | cut -c1-16)
    LAST=$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$LOG" | tail -n1 | cut -c1-16)
fi

# --- Tabelle der AUSSERHALB-Zugriffe ---------------------------------------
OUTSIDE_ROWS=""
if [ -f "$LOG" ]; then
    OUTSIDE_ROWS=$(grep -F '[AUSSERHALB]' "$LOG" | tac | while IFS= read -r line; do
        ts="${line:0:19}"
        tool=$(printf '%s' "$line" | sed -n 's/.*\[AUSSERHALB\] \[\([^]]*\)\].*/\1/p')
        path=$(printf '%s' "$line" | sed 's/.*\[AUSSERHALB\] \[[^]]*\] //' | esc)
        printf '<tr><td class="time">%s</td><td><span class="tool">%s</span></td><td class="path">%s</td></tr>\n' \
            "$ts" "$tool" "$path"
    done)
fi
if [ -z "$OUTSIDE_ROWS" ]; then
    OUTSIDE_ROWS='<tr><td colspan="3" class="empty">Keine – alles blieb im Projektordner oder auf der Allowlist.</td></tr>'
fi

# --- Zugriffe einlesen (ohne AUSSERHALB-Duplikate und Fehlerzeilen) ---------
ACC_EPOCH=(); ACC_HTML=()
if [ -f "$LOG" ]; then
    while IFS= read -r line; do
        stamp="${line:0:19}"
        epoch=$(date -d "$stamp" '+%s' 2>/dev/null) || continue
        tool=$(printf '%s' "$line" | sed -n 's/^[0-9: -]\{19\} \[\([^]]*\)\].*/\1/p')
        path=$(printf '%s' "$line" | sed 's/^[0-9: -]\{19\} \[[^]]*\] //' | esc)
        ACC_EPOCH+=("$epoch")
        ACC_HTML+=("<tr><td class=\"time\">${stamp:11:5}</td><td><span class=\"tool\">$tool</span></td><td class=\"path\">$path</td></tr>")
    done < <(grep -v -e '\[AUSSERHALB\]' -e '\[FEHLER\]' "$LOG")
fi

# --- Prompts einlesen und Zeitfenster bilden --------------------------------
TIMELINE=""
PROMPT_TS=(); PROMPT_TXT=()
if command -v jq >/dev/null 2>&1 && [ -f "$HIST" ]; then
    while IFS=$'\t' read -r ts txt; do
        [ -z "$ts" ] && continue
        PROMPT_TS+=("$ts"); PROMPT_TXT+=("$txt")
    done < <(jq -r 'select(type == "object" and .timestamp != null and .display != null)
                    | "\(.timestamp / 1000 | floor)\t\(.display | gsub("[\\n\\t]"; " "))"' \
             "$HIST" 2>/dev/null | sort -n)
fi

if [ "${#PROMPT_TS[@]}" -gt 0 ]; then
    n=${#PROMPT_TS[@]}
    start=$(( n > MAX_PROMPTS ? n - MAX_PROMPTS : 0 ))
    for (( i = n - 1; i >= start; i-- )); do
        wstart=${PROMPT_TS[$i]}
        if [ "$i" -lt $(( n - 1 )) ]; then wend=${PROMPT_TS[$((i+1))]}; else wend=""; fi
        rows=""
        count=0
        for (( j = 0; j < ${#ACC_EPOCH[@]}; j++ )); do
            e=${ACC_EPOCH[$j]}
            if [ "$e" -ge "$wstart" ] && { [ -z "$wend" ] || [ "$e" -lt "$wend" ]; }; then
                rows+="${ACC_HTML[$j]}"$'\n'
                count=$((count+1))
            fi
        done
        [ "$count" -eq 0 ] && continue
        if [ "$count" -eq 1 ]; then einheit="Zugriff"; else einheit="Zugriffe"; fi
        ptime=$(date -d "@$wstart" '+%d.%m.%Y %H:%M')
        ptext=$(printf '%s' "${PROMPT_TXT[$i]}" | cut -c1-300 | esc)
        TIMELINE+="<details><summary><span class=\"ptime\">$ptime</span> $ptext <span class=\"count\">$count $einheit</span></summary>
<table><thead><tr><th>Zeit</th><th>Tool</th><th>Pfad</th></tr></thead><tbody>
$rows</tbody></table></details>
"
    done
fi
if [ -z "$TIMELINE" ]; then
    TIMELINE='<p class="empty">Keine zuordenbaren Prompts gefunden (History fehlt, Format unbekannt oder noch keine Zugriffe in den Zeitfenstern).</p>'
fi

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
.empty{color:var(--ink2);padding:14px}
details{background:var(--surface);border:1px solid var(--line);border-radius:10px;margin-bottom:10px;overflow-x:auto}
summary{cursor:pointer;padding:12px 16px;list-style-position:inside}
summary:hover{color:var(--accent)}
.ptime{color:var(--ink2);font-variant-numeric:tabular-nums;margin-right:6px}
.count{color:var(--ink2);font-size:.82rem;white-space:nowrap}
.warnbox{background:var(--warn-bg);color:var(--warn-ink);border-radius:10px;padding:12px 16px;font-size:.88rem;margin-top:8px}
.note{color:var(--ink2);font-size:.85rem;margin-top:6px}
</style>
</head>
<body>
<main>
<h1>claude-readguard – Bericht</h1>
<p class="sub">Stand: $STAND · rein lokale Datei, kein Server, nichts verlässt diesen Rechner</p>

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

<h2>Prompts und nachfolgende Zugriffe</h2>
<p class="note">Neueste zuerst, aufklappbar, maximal $MAX_PROMPTS Prompts. Die Zuordnung erfolgt nur über Zeitstempel und ist eine <strong>Näherung</strong> – parallele Sitzungen verfälschen sie.</p>
$TIMELINE

<div class="warnbox"><strong>Datenschutz:</strong> Diese Datei enthält echte Pfad- und Projektnamen und ggf. komplette Bash-Kommandozeilen. Nicht weitergeben, nicht in ein Repository legen.</div>
</main>
</body>
</html>
HTML

echo "Bericht geschrieben: $OUT"
if [ "${1:-}" != "--no-open" ]; then
    xdg-open "$OUT" >/dev/null 2>&1 &
fi
