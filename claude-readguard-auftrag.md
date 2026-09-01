# Auftrag: claude-readguard einrichten

Baue mir ein kleines Tool namens **claude-readguard** und richte es auf diesem Rechner ein.

## Zweck

Ich kann nicht programmieren und will deshalb nicht den Code prüfen, sondern das
Verhalten. Ich will wissen, welche Dateien Claude Code **von sich aus** liest —
also ohne dass ich es ausdrücklich angewiesen habe — und ich will gefragt werden,
bevor auf etwas ausserhalb meines Projektordners zugegriffen wird.

## Was gebaut werden soll

Ein PreToolUse-Hook plus zwei Hilfsskripte:

1. **Hook** (`~/.claude-readguard/readguard.sh`)
   - wird bei den Tools `Read`, `Glob`, `Grep`, `Bash`, `NotebookRead` aufgerufen
   - liest das Hook-JSON von stdin, braucht `jq`
   - Zielpfad steht je nach Tool in `.tool_input.file_path`, `.path`,
     `.notebook_path` oder `.command`
   - schreibt jeden Zugriff als `ZEIT [TOOL] PFAD` nach `~/.claude-readguard/reads.log`
   - **filtert Rauschen komplett heraus** (nicht loggen, nicht fragen):
     `.claude/`, `.claude.json`, `.npm/`, `.cache/claude`, `node_modules/`,
     `.config/claude` — das liest Claude Code bei jedem Start selbst
   - Zugriffe **innerhalb** von `.cwd` und relative Pfade: durchlassen
   - bei Tool `Bash`: nur protokollieren, nicht blockieren (dort steht nur der
     Kommandotext, nicht die tatsächlich gelesenen Dateien)
   - Muster aus `~/.claude-readguard/allowlist` (eins pro Zeile, `#` = Kommentar,
     Wildcards erlaubt): durchlassen
   - alles andere: zusätzlich als `[AUSSERHALB]` loggen und eine Rückfrage
     auslösen über die JSON-Ausgabe
     `{"hookSpecificOutput":{"hookEventName":"PreToolUse",
     "permissionDecision":"ask","permissionDecisionReason":"..."}}`
   - immer mit `exit 0` enden, nie Claude Code blockieren
   - wenn `jq` fehlt: Fehlerzeile ins Log, aber durchlassen

2. **install.sh**
   - kopiert den Hook nach `~/.claude-readguard/`, macht ihn ausführbar
   - legt eine kommentierte Beispiel-`allowlist` an
   - trägt den Hook per `jq` in `~/.claude/settings.json` unter
     `hooks.PreToolUse` ein, Matcher `Read|Glob|Grep|Bash|NotebookRead`
   - **legt vorher ein Backup der settings.json an**
   - prüft, ob `jq` installiert ist, sonst Hinweis auf `sudo apt install jq`

3. **report.sh**
   - listet zuerst alle `[AUSSERHALB]`-Treffer
   - stellt danach meine Prompts aus `~/.claude/history.jsonl` (Feld
     `.timestamp` in Epoch-Millisekunden, Feld `.display`) und die zeitlich
     darauf folgenden Zugriffe aus dem Log nebeneinander
   - wenn das history-Format nicht passt: nicht abstürzen, sondern auf die
     reine Zugriffsliste zurückfallen
   - Hinweis ausgeben, dass die Zuordnung über Zeitstempel nur eine Näherung ist

## Dazu

- README auf Deutsch, mit einem ehrlichen Abschnitt **"Was es nicht leistet"**:
  geöffnet ist nicht übertragen; Bash-Befehle sind eine Lücke; keine Sandbox,
  echte Grenzen liegen auf Betriebssystemebene; die Serverseite bleibt unberührt
- Warnung im README, dass `reads.log` echte Pfad- und Projektnamen enthält und
  nicht in ein Repository gehört
- `.gitignore` für `reads.log`, `allowlist`, `*.bak.*`
- MIT-Lizenz

## Prüfen bevor du fertig meldest

Teste den Hook mit vier künstlichen JSON-Eingaben und zeig mir die Ergebnisse:

1. Datei **im** Projektordner → still, wird geloggt
2. Pfad unter `~/.claude/` → still, wird **nicht** geloggt
3. `~/.ssh/id_rsa` → Rückfrage-JSON auf stdout, `[AUSSERHALB]` im Log
4. Pfad aus der allowlist → still, geloggt, keine Rückfrage

Danach: `bash -n` über alle Skripte.

## Am Ende

Sag mir, was ich noch selbst tun muss, und trag diese drei Pfade gleich in die
allowlist ein, weil Claude Code sie routinemässig liest und sie sonst bei jedem
Start eine Rückfrage auslösen:

    ~/.gitconfig
    ~/.config/gh/hosts.yml
    ~/.npmrc
