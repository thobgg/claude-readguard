# claude-readguard

Ein kleiner PreToolUse-Hook für Claude Code, der sichtbar macht, welche Dateien
Claude Code liest – und der **nachfragt**, bevor auf etwas ausserhalb des
Projektordners zugegriffen wird.

Gedacht für alle, die nicht den Code prüfen wollen, sondern das Verhalten:
Was liest Claude Code von sich aus, ohne dass ich es ausdrücklich angewiesen
habe?

Der Clou: Wer es lückenlos will, startet die Sitzung mit **`claude-audit`**
statt `claude` – dann protokolliert das **Betriebssystem** jede einzelne
Dateiöffnung, auch innerhalb von Bash-Befehlen. Keine Selbstauskunft der KI,
sondern unabhängige Messung ([Details](#lückenlose-aufzeichnung-claude-audit)).

![HTML-Bericht von claude-readguard (Demo-Daten)](screenshot.png)

*Der HTML-Bericht (`readguard-html`) – Screenshot mit Demo-Daten.*

## Funktionsweise

Der Hook (`~/.claude-readguard/readguard.sh`) wird vor jedem Aufruf der Tools
`Read`, `Glob`, `Grep`, `Bash` und `NotebookRead` ausgeführt und

- protokolliert jeden Zugriff als `ZEIT [TOOL] PFAD` in
  `~/.claude-readguard/reads.log`,
- lässt Zugriffe **innerhalb** des Projektordners und relative Pfade still
  durch,
- filtert Claude-Code-eigenes Rauschen komplett heraus (`.claude/`,
  `.claude.json`, `.npm/`, `.cache/claude`, `node_modules/`,
  `.config/claude`) – das liest Claude Code bei jedem Start selbst,
- lässt Pfade durch, die in `~/.claude-readguard/allowlist` stehen
  (ein Muster pro Zeile, `#` = Kommentar, Wildcards erlaubt),
- markiert alles andere zusätzlich als `[AUSSERHALB]` im Log und löst in
  Claude Code eine **Rückfrage** aus, bevor der Zugriff stattfindet,
- protokolliert bei `Bash` nur den Kommandotext, blockiert aber nicht
  (siehe unten).

## Sperren statt nachfragen: die Sperrliste

Der Readguard fragt nur nach. Wer bestimmte Orte **ganz** verschliessen will,
trägt sie in `~/.claude-readguard/sperrliste` ein – ein regulärer Ausdruck je
Zeile, Gross/Klein egal. Der zweite Hook (`sperrliste-hook.sh`) prüft damit
**jede** Werkzeugeingabe, also auch Bash-Kommandos, Edit und Write, und
verweigert den Aufruf mit einer Begründung, die Claude Code anzeigt. Jede
Verweigerung steht als `[GESPERRT]` im Log. Änderungen an der Liste gelten
sofort, ohne Neustart.

Eine Sperrliste kann keine Ausnahmen („alles ausser …“) ausdrücken. Dafür
liegen unter `beispiele/` zwei eigene Hooks, die sich als Vorlage anpassen
lassen: `photos-sperre.sh` sperrt Fotoordner lokal und auf der NAS,
`dokumente-sperre.sh` sperrt den Dokumente-Ordner bis auf einen Unterordner.
Beide enthalten feste Pfade und werden nicht vom Installer übernommen; sie
wollen von Hand in `settings.json` eingetragen werden, mit demselben Matcher
wie der Sperrlisten-Hook.

## Installation

```
bash install.sh
```

Das Skript kopiert beide Hooks nach `~/.claude-readguard/`, legt eine
kommentierte Beispiel-`allowlist` und -`sperrliste` an und registriert die
Hooks in `~/.claude/settings.json`. Von der settings.json wird vorher ein Backup
angelegt (`settings.json.bak.DATUM`). Benötigt wird `jq`
(`sudo apt install jq`).

Bereits laufende Claude-Code-Sitzungen müssen neu gestartet werden, damit der
Hook greift.

## Auswertung

Zwei Wege, gleicher Inhalt:

```
readguard-report        # Textbericht im Terminal
readguard-html          # HTML-Bericht im Browser (rein lokal, kein Server)
```

Der HTML-Bericht wird nach `~/.claude-readguard/report.html` geschrieben und
über `file://` im Standardbrowser geöffnet – es läuft kein Server, nichts
verlässt den Rechner. Der Startmenü-Eintrag **„Readguard"** öffnet die Fenster-App (siehe unten),
aus der sich der HTML-Bericht ebenfalls erzeugen lässt.

Beide Berichte zeigen zuerst alle `[AUSSERHALB]`-Treffer, danach eine
Ordner-Übersicht (wo wurde wie oft gelesen), die zuletzt ausgeführten
Bash-Befehle und die vollständige Zugriffsliste. **Bewusst ohne
Chat-Inhalte:** Die eigenen Prompts erscheinen nirgends im Bericht – der
Fokus liegt auf den Dateizugriffen.
**Achtung:** Diese Zuordnung erfolgt nur über Zeitstempel und ist eine
Näherung – bei parallelen Sitzungen stimmt sie nicht zuverlässig. Passt das
History-Format nicht, fällt das Skript auf die reine Zugriffsliste zurück.

## Fenster-App

```
readguard-app           # oder im Startmenü: „Readguard“
```

Ein kleines Fenster mit denselben Inhalten wie der Bericht, dazu ein
Zeitraumfilter (heute, 7 Tage, 30 Tage, alles), ein Reiter für gesperrte
Aufrufe und Knöpfe für die Allowlist und die Sperrliste (Änderungen gelten
sofort), den HTML-Bericht und **„Log kürzen“**: Ältere Zeilen wandern gepackt
nach `~/.claude-readguard/reads-bis-DATUM.log.gz`, das Log bleibt handlich.
Doppelklick auf eine Zeile zeigt den vollen Eintrag. Braucht nur Python 3
mit Tkinter (`sudo apt install python3-tk`), sonst nichts.

### Windows (experimentell)

Die App läuft unter Windows mit dem normalen Python von python.org;
`install.ps1` legt eine Startmenü-Verknüpfung „Readguard“ an:

```
powershell -ExecutionPolicy Bypass -File install.ps1
```

Der Hook selbst ist ein Bash-Skript und braucht unter Windows Git Bash und
`jq`; `install.sh` ist dort in Git Bash auszuführen. Das ist bislang nicht auf
einem Windows-Rechner geprüft. Ohne laufenden Hook zeigt die App ein leeres Log.

## Lückenlose Aufzeichnung: `claude-audit`

Der Hook hat prinzipbedingt eine Lücke: Bei Bash-Befehlen sieht er nur den
Kommandotext, nicht die Dateien, die der Befehl wirklich öffnet. Wer es
lückenlos will, startet Claude Code so:

```
claude-audit
```

Alle gewohnten Argumente funktionieren weiter und werden unverändert
durchgereicht, z. B. `claude-audit --resume` oder `claude-audit --continue`.

Das startet Claude Code unter `strace` – das Betriebssystem zeichnet dann
**jede** Dateiöffnung von Claude Code und allen Unterprozessen auf, auch
innerhalb von Bash-Befehlen. Nach dem Beenden der Sitzung erscheint
automatisch die Auswertung: alle geöffneten Dateien, sortiert nach innerhalb
und ausserhalb des Projektordners, System-Rauschen herausgefiltert. Später
erneut anzeigen: `readguard-audit`. Benötigt `strace`
(`sudo apt install strace`); die Sitzung läuft dadurch etwas langsamer.

Diese Liste kommt vom Betriebssystem, nicht von Claude selbst – sie ist
unabhängig von jeder Selbstauskunft.

## Was es nicht leistet

Ehrlichkeit vor Marketing – dieses Tool hat klare Grenzen:

- **Geöffnet ist nicht übertragen.** Das Log zeigt, welche Dateien geöffnet
  wurden, nicht, welche Inhalte tatsächlich an die Anthropic-Server gesendet
  wurden.
- **Der Hook allein hat eine Bash-Lücke.** Bei `Bash` steht im Hook nur der
  Kommandotext, nicht die Dateien, die der Befehl dann wirklich liest. Ein
  `cat ~/.ssh/id_rsa` innerhalb eines Bash-Befehls wird protokolliert, aber
  nicht blockiert. Diese Lücke schliesst erst `claude-audit` (siehe oben) –
  allerdings nur aufzeichnend, nicht blockierend.
- **Keine Sandbox.** Ein Hook ist eine Konvention, keine Durchsetzung. Echte
  Grenzen liegen auf Betriebssystemebene (eigene Benutzerkonten, Container,
  Dateirechte, AppArmor/SELinux). Ein kleiner Schritt in diese Richtung:
  `sudo chattr +i ~/.claude-readguard/*.sh` macht die installierten Hooks
  unveränderbar, auch für Claude Code selbst; `install.sh` überspringt solche
  Dateien dann.
- **Die Serverseite bleibt unberührt.** Was mit übertragenen Daten bei
  Anthropic passiert, kann ein lokales Tool weder sehen noch beeinflussen.

## Datenschutz-Warnung

`reads.log` enthält **echte Pfad- und Projektnamen** von diesem Rechner und
unter Umständen komplette Bash-Kommandozeilen. Diese Datei gehört **nicht in
ein Repository** und nicht in geteilte Ordner. Die mitgelieferte `.gitignore`
schliesst `reads.log`, `allowlist`, `sperrliste`, `report.html`, die
`audit/`-Aufzeichnungen und Backups aus.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
