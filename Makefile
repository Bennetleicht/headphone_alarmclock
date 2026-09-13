# Entwicklung unter Linux -- kein Xcode noetig.
#
#   make check    Projektbeschreibung und Quellen pruefen
#   make icon     App-Icon neu erzeugen
#   make parse    Swift-Syntaxpruefung (nur mit installierter Swift-Toolchain)
#   make tree     Projektstruktur anzeigen

.PHONY: check icon parse tree help

help:
	@grep -E '^#   ' Makefile | sed 's/^#   //'

check:
	@python3 Tools/check_project.py

icon:
	@python3 Tools/make_appicon.py

parse:
	@command -v swiftc >/dev/null 2>&1 || { \
		echo "swiftc nicht gefunden - siehe https://swift.org/download"; exit 1; }
	@find Sources -name '*.swift' -print0 | xargs -0 swiftc -parse
	@echo "Syntax in Ordnung."

tree:
	@find . -path ./.git -prune -o -type f -print | sort
