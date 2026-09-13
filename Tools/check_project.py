#!/usr/bin/env python3
"""Pruefungen, die ohne Xcode und ohne macOS laufen.

Faengt genau die Fehler ab, die sich unter Linux einschleichen und sonst erst
zehn Minuten spaeter im CI auffallen:

* `project.yml` ist kein gueltiges YAML
* Ein Asset-Catalog-`Contents.json` ist kaputt
* Eine Swift-Datei liegt ausserhalb von `Sources/TrainAlarm`
* Klammern oder Anfuehrungszeichen sind unbalanciert
* Pflichtangaben im Info.plist-Abschnitt fehlen

    python3 Tools/check_project.py
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT / "Sources" / "TrainAlarm"

REQUIRED_PLIST_KEYS = [
    "UIBackgroundModes",
    "CFBundleDisplayName",
    "UILaunchScreen",
]

problems: list[str] = []
notes: list[str] = []


def check_project_yaml() -> None:
    spec = ROOT / "project.yml"
    if not spec.exists():
        problems.append("project.yml fehlt")
        return

    text = spec.read_text()

    try:
        import yaml  # type: ignore
    except ImportError:
        notes.append("PyYAML nicht installiert - project.yml nur oberflaechlich geprueft")
        for key in REQUIRED_PLIST_KEYS:
            if key not in text:
                problems.append(f"project.yml: Schluessel '{key}' fehlt")
        if "audio" not in text:
            problems.append("project.yml: Hintergrundmodus 'audio' fehlt")
        return

    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as error:
        problems.append(f"project.yml ist kein gueltiges YAML: {error}")
        return

    target = (data.get("targets") or {}).get("TrainAlarm")
    if not target:
        problems.append("project.yml: Target 'TrainAlarm' fehlt")
        return

    plist = (target.get("info") or {}).get("properties") or {}
    for key in REQUIRED_PLIST_KEYS:
        if key not in plist:
            problems.append(f"project.yml: Info.plist-Schluessel '{key}' fehlt")

    if "audio" not in (plist.get("UIBackgroundModes") or []):
        problems.append("project.yml: UIBackgroundModes enthaelt kein 'audio' - "
                        "ohne das laeuft der Wecker im Hintergrund nicht")

    settings = target.get("settings", {}).get("base", {})
    if not settings.get("PRODUCT_BUNDLE_IDENTIFIER"):
        problems.append("project.yml: PRODUCT_BUNDLE_IDENTIFIER fehlt")


def check_asset_catalog() -> None:
    catalog = ROOT / "Resources" / "Assets.xcassets"
    if not catalog.exists():
        problems.append("Resources/Assets.xcassets fehlt")
        return

    for contents in catalog.rglob("Contents.json"):
        try:
            json.loads(contents.read_text())
        except json.JSONDecodeError as error:
            problems.append(f"{contents.relative_to(ROOT)}: ungueltiges JSON ({error})")

    icon = catalog / "AppIcon.appiconset" / "AppIcon-1024.png"
    if not icon.exists():
        problems.append("App-Icon fehlt - 'make icon' ausfuehren")


def strip_swift(text: str) -> str:
    """Entfernt Kommentare und String-Literale grob, damit die Klammerpruefung
    nicht an einer geschweiften Klammer im Fliesstext scheitert."""
    text = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    text = re.sub(r'\\\(', '(', text)          # String-Interpolation entschaerfen
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*(?:.|\n)*?\*/', '', text)
    return text


def check_swift_sources() -> None:
    if not SOURCE_ROOT.exists():
        problems.append("Sources/TrainAlarm fehlt")
        return

    stray = [
        path for path in ROOT.rglob("*.swift")
        if SOURCE_ROOT not in path.parents and ".build" not in path.parts
    ]
    for path in stray:
        problems.append(f"{path.relative_to(ROOT)} liegt ausserhalb von Sources/TrainAlarm "
                        "und wird nicht mitgebaut")

    files = sorted(SOURCE_ROOT.rglob("*.swift"))
    if not files:
        problems.append("keine Swift-Dateien gefunden")
        return

    for path in files:
        cleaned = strip_swift(path.read_text())
        for opener, closer, label in (("{", "}", "geschweifte"), ("(", ")", "runde"), ("[", "]", "eckige")):
            if cleaned.count(opener) != cleaned.count(closer):
                problems.append(
                    f"{path.relative_to(ROOT)}: {label} Klammern unbalanciert "
                    f"({cleaned.count(opener)}x '{opener}', {cleaned.count(closer)}x '{closer}')"
                )

    notes.append(f"{len(files)} Swift-Dateien geprueft")


def check_workflow() -> None:
    workflow = ROOT / ".github" / "workflows" / "build.yml"
    if not workflow.exists():
        problems.append(".github/workflows/build.yml fehlt")
        return
    text = workflow.read_text()
    if "CODE_SIGNING_ALLOWED=NO" not in text:
        problems.append("build.yml: Build ist nicht als unsigniert konfiguriert")
    if "package-ipa.sh" not in text:
        problems.append("build.yml: IPA-Paketierung fehlt")

    script = ROOT / "Scripts" / "package-ipa.sh"
    if not script.exists():
        problems.append("Scripts/package-ipa.sh fehlt")


def main() -> int:
    check_project_yaml()
    check_asset_catalog()
    check_swift_sources()
    check_workflow()

    for note in notes:
        print(f"  info   {note}")

    if problems:
        print()
        for problem in problems:
            print(f"  FEHLER {problem}")
        print(f"\n{len(problems)} Problem(e) gefunden.")
        return 1

    print("\nAlles in Ordnung. Der eigentliche Compiler-Lauf passiert im CI.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
