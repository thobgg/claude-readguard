#!/usr/bin/env python3
"""claude-readguard – Fenster-App für Linux und Windows.

Zeigt reads.log übersichtlich an (Zugriffe ausserhalb des Projektordners,
gesperrte Aufrufe, Ordner-Übersicht, Bash-Befehle), öffnet Allowlist und
Sperrliste zum Bearbeiten, erzeugt den HTML-Bericht und kürzt das Log.
Braucht nur Python 3 mit Tkinter, keine weiteren Pakete. Rein lokal.
"""
import gzip
import re
import shutil
import subprocess
import sys
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path

import tkinter as tk
from tkinter import messagebox, scrolledtext, simpledialog, ttk

DIR = Path.home() / ".claude-readguard"
LOG = DIR / "reads.log"
ALLOWLIST = DIR / "allowlist"
SPERRLISTE = DIR / "sperrliste"
REPORT = DIR / "report.html"
HERE = Path(__file__).resolve().parent

ZEILE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[([A-Za-z]+)\] ?(.*)$")
AUSSEN = re.compile(r"^\[([^\]]+)\] (.*)$")
ZEITRAEUME = {"Heute": 0, "7 Tage": 7, "30 Tage": 30, "Alles": None}
MAX_ZEILEN = 5000  # Obergrenze je Tabelle, damit die Anzeige flüssig bleibt


class Eintrag:
    __slots__ = ("ts", "art", "tool", "text")

    def __init__(self, ts, art, tool, text):
        self.ts, self.art, self.tool, self.text = ts, art, tool, text


def lesen(pfad=LOG):
    """Liest das Log. Zeilen ohne Zeitstempel hängen am vorigen Eintrag
    (mehrzeilige Bash-Befehle aus den ersten Tagen)."""
    eintraege = []
    if not pfad.exists():
        return eintraege
    with open(pfad, encoding="utf-8", errors="replace") as f:
        for roh in f:
            roh = roh.rstrip("\n")
            m = ZEILE.match(roh)
            if not m:
                if eintraege:
                    eintraege[-1].text += " ⏎ " + roh
                continue
            ts, tag, rest = m.groups()
            if tag == "AUSSERHALB":
                a = AUSSEN.match(rest)
                tool, text = (a.group(1), a.group(2)) if a else ("?", rest)
                eintraege.append(Eintrag(ts, "aussen", tool, text))
            elif tag == "GESPERRT":
                tool, _, text = rest.partition(" ")
                eintraege.append(Eintrag(ts, "gesperrt", tool, text))
            elif tag == "FEHLER":
                eintraege.append(Eintrag(ts, "fehler", "-", rest))
            else:
                eintraege.append(Eintrag(ts, "zugriff", tag, rest))
    return eintraege


def ordner_kurz(pfad):
    """/a/b/c/d/e -> /a/b/c/… wie im Shell-Bericht."""
    teile = pfad.split("/")
    if len(teile) > 4:
        return "/".join(teile[:4]) + "/…"
    return pfad


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Readguard")
        self.geometry("1100x700")
        self.minsize(760, 480)
        if sys.platform.startswith("linux"):
            try:
                ttk.Style(self).theme_use("clam")
            except tk.TclError:
                pass
        self.alle = []
        self.tabellen = {}
        self.bauen()
        self.laden()

    # ---------- Aufbau ----------
    def bauen(self):
        kopf = ttk.Frame(self, padding=(12, 10, 12, 4))
        kopf.pack(fill="x")
        ttk.Label(kopf, text="Zeitraum:").pack(side="left")
        self.zeitraum = tk.StringVar(value="30 Tage")
        box = ttk.Combobox(kopf, textvariable=self.zeitraum, values=list(ZEITRAEUME),
                           state="readonly", width=9)
        box.pack(side="left", padx=(4, 16))
        box.bind("<<ComboboxSelected>>", lambda e: self.anzeigen())
        ttk.Button(kopf, text="Neu laden", command=self.laden).pack(side="left")
        self.status = ttk.Label(kopf, text="", foreground="#666")
        self.status.pack(side="right")

        self.kennzahlen = ttk.Frame(self, padding=(12, 4))
        self.kennzahlen.pack(fill="x")
        self.kz = {}
        for key, titel in (("zugriffe", "Zugriffe"), ("aussen", "ausserhalb des Projekts"),
                           ("gesperrt", "gesperrt"), ("bash", "Bash-Befehle")):
            f = ttk.Frame(self.kennzahlen, relief="groove", padding=(14, 6))
            f.pack(side="left", padx=(0, 10))
            zahl = ttk.Label(f, text="–", font=("TkDefaultFont", 18, "bold"))
            zahl.pack()
            ttk.Label(f, text=titel, foreground="#666").pack()
            self.kz[key] = zahl

        self.mappen = ttk.Notebook(self)
        self.mappen.pack(fill="both", expand=True, padx=12, pady=6)
        self.tabelle("aussen", "Ausserhalb des Projekts",
                     (("Zeit", 130), ("Tool", 80), ("Pfad", 700)))
        self.tabelle("gesperrt", "Gesperrt",
                     (("Zeit", 130), ("Tool", 80), ("Eingabe", 700)))
        self.tabelle("ordner", "Ordner-Übersicht",
                     (("Ordner", 700), ("Zugriffe", 100)))
        self.tabelle("bash", "Bash-Befehle",
                     (("Zeit", 130), ("Befehl", 800)))
        self.tabelle("alle", "Alle Zugriffe",
                     (("Zeit", 130), ("Tool", 80), ("Pfad", 700)))

        fuss = ttk.Frame(self, padding=(12, 4, 12, 10))
        fuss.pack(fill="x")
        ttk.Button(fuss, text="Allowlist…", command=lambda: self.editor(ALLOWLIST, "Allowlist")).pack(side="left")
        ttk.Button(fuss, text="Sperrliste…", command=lambda: self.editor(SPERRLISTE, "Sperrliste")).pack(side="left", padx=6)
        ttk.Button(fuss, text="HTML-Bericht", command=self.html_bericht).pack(side="left")
        ttk.Button(fuss, text="Log kürzen…", command=self.log_kuerzen).pack(side="right")
        ttk.Label(fuss, text=str(LOG), foreground="#666").pack(side="right", padx=12)

    def tabelle(self, key, titel, spalten):
        rahmen = ttk.Frame(self.mappen)
        self.mappen.add(rahmen, text=titel)
        namen = [s[0] for s in spalten]
        tv = ttk.Treeview(rahmen, columns=namen, show="headings", selectmode="browse")
        for name, breite in spalten:
            tv.heading(name, text=name)
            tv.column(name, width=breite, anchor="e" if name == "Zugriffe" else "w",
                      stretch=(breite >= 700))
        sb = ttk.Scrollbar(rahmen, orient="vertical", command=tv.yview)
        tv.configure(yscrollcommand=sb.set)
        tv.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        tv.bind("<Double-1>", lambda e, t=tv: self.details(t))
        self.tabellen[key] = tv

    # ---------- Daten ----------
    def laden(self):
        self.alle = lesen()
        self.anzeigen()

    def gefiltert(self):
        tage = ZEITRAEUME[self.zeitraum.get()]
        if tage is None:
            return self.alle
        ab = (datetime.now() - timedelta(days=tage)).strftime("%Y-%m-%d") if tage else datetime.now().strftime("%Y-%m-%d")
        return [e for e in self.alle if e.ts[:10] >= ab]

    def anzeigen(self):
        eintr = self.gefiltert()
        zugriffe = [e for e in eintr if e.art == "zugriff"]
        aussen = [e for e in eintr if e.art == "aussen"]
        gesperrt = [e for e in eintr if e.art == "gesperrt"]
        bash = [e for e in zugriffe if e.tool == "Bash"]

        self.kz["zugriffe"].config(text=f"{len(zugriffe):,}".replace(",", "."))
        self.kz["aussen"].config(text=str(len(aussen)))
        self.kz["gesperrt"].config(text=str(len(gesperrt)))
        self.kz["bash"].config(text=f"{len(bash):,}".replace(",", "."))

        self.fuellen("aussen", [(e.ts[:16], e.tool, e.text) for e in reversed(aussen)])
        self.fuellen("gesperrt", [(e.ts[:16], e.tool, e.text) for e in reversed(gesperrt)])
        zaehler = {}
        for e in zugriffe:
            if e.tool != "Bash":
                k = ordner_kurz(e.text)
                zaehler[k] = zaehler.get(k, 0) + 1
        self.fuellen("ordner", sorted(zaehler.items(), key=lambda kv: -kv[1]))
        self.fuellen("bash", [(e.ts[:16], e.text) for e in reversed(bash)])
        self.fuellen("alle", [(e.ts[:16], e.tool, e.text) for e in reversed(zugriffe)])

        if self.alle:
            self.status.config(text=f"{self.alle[0].ts[:16]} bis {self.alle[-1].ts[:16]} · "
                                    f"{len(self.alle):,} Zeilen".replace(",", "."))
        else:
            self.status.config(text="Noch kein Log vorhanden.")
        self.mappen.tab(0, text=f"Ausserhalb des Projekts ({len(aussen)})")
        self.mappen.tab(1, text=f"Gesperrt ({len(gesperrt)})")

    def fuellen(self, key, zeilen):
        tv = self.tabellen[key]
        tv.delete(*tv.get_children())
        for z in zeilen[:MAX_ZEILEN]:
            tv.insert("", "end", values=[str(v)[:300] for v in z])
        if len(zeilen) > MAX_ZEILEN:
            tv.insert("", "end", values=["…", f"{len(zeilen) - MAX_ZEILEN} weitere Zeilen, Zeitraum einschränken"])
        if not zeilen:
            tv.insert("", "end", values=["(keine)"])

    def details(self, tv):
        auswahl = tv.selection()
        if not auswahl:
            return
        werte = tv.item(auswahl[0], "values")
        fenster = tk.Toplevel(self)
        fenster.title("Eintrag")
        fenster.geometry("800x300")
        txt = scrolledtext.ScrolledText(fenster, wrap="word", font=("TkFixedFont", 10))
        txt.pack(fill="both", expand=True)
        txt.insert("1.0", "\n".join(str(w) for w in werte))
        txt.config(state="disabled")

    # ---------- Aktionen ----------
    def editor(self, pfad, titel):
        fenster = tk.Toplevel(self)
        fenster.title(f"{titel} – {pfad}")
        fenster.geometry("760x480")
        txt = scrolledtext.ScrolledText(fenster, wrap="none", font=("TkFixedFont", 10), undo=True)
        txt.pack(fill="both", expand=True)
        inhalt = pfad.read_text(encoding="utf-8") if pfad.exists() else ""
        txt.insert("1.0", inhalt)

        def speichern():
            pfad.parent.mkdir(parents=True, exist_ok=True)
            pfad.write_text(txt.get("1.0", "end-1c"), encoding="utf-8")
            fenster.destroy()

        leiste = ttk.Frame(fenster, padding=6)
        leiste.pack(fill="x")
        ttk.Label(leiste, text="Ein Muster je Zeile, # = Kommentar. Gilt sofort.",
                  foreground="#666").pack(side="left")
        ttk.Button(leiste, text="Speichern", command=speichern).pack(side="right")
        ttk.Button(leiste, text="Abbrechen", command=fenster.destroy).pack(side="right", padx=6)

    def html_bericht(self):
        skript = HERE / "report-html.sh"
        bash = shutil.which("bash")
        if not (skript.exists() and bash):
            messagebox.showinfo("HTML-Bericht", "Dafür werden report-html.sh im Programmordner und bash gebraucht.")
            return
        ergebnis = subprocess.run([bash, str(skript), "--no-open"], capture_output=True, text=True)
        if ergebnis.returncode != 0:
            messagebox.showerror("HTML-Bericht", ergebnis.stderr or "Bericht konnte nicht erzeugt werden.")
            return
        webbrowser.open(REPORT.as_uri())

    def log_kuerzen(self):
        if not LOG.exists():
            messagebox.showinfo("Log kürzen", "Es gibt noch kein Log.")
            return
        tage = simpledialog.askinteger("Log kürzen", "Wie viele Tage sollen im Log bleiben?\n"
                                       "Ältere Zeilen wandern gepackt ins Archiv.",
                                       initialvalue=30, minvalue=1, maxvalue=3650, parent=self)
        if not tage:
            return
        grenze = (datetime.now() - timedelta(days=tage)).strftime("%Y-%m-%d")
        with open(LOG, encoding="utf-8", errors="replace") as f:
            zeilen = f.readlines()
        alt, neu, behalten = [], [], False
        for z in zeilen:
            m = ZEILE.match(z)
            if m:
                behalten = m.group(1)[:10] >= grenze
            (neu if behalten else alt).append(z)
        if not alt:
            messagebox.showinfo("Log kürzen", f"Nichts zu tun, alle Zeilen sind jünger als {tage} Tage.")
            return
        archiv = DIR / f"reads-bis-{grenze}.log.gz"
        with gzip.open(archiv, "at", encoding="utf-8") as g:
            g.writelines(alt)
        with open(LOG, "w", encoding="utf-8") as f:
            f.writelines(neu)
        groesse = archiv.stat().st_size // 1024
        messagebox.showinfo("Log kürzen", f"{len(alt):,} Zeilen archiviert nach\n{archiv}\n({groesse} KB), "
                                          f"{len(neu):,} Zeilen bleiben.".replace(",", "."))
        self.laden()


def main():
    App().mainloop()


if __name__ == "__main__":
    main()
