#!/usr/bin/env bash
#
# Packt ein gebautes .app-Bundle in eine .ipa.
#
# Eine .ipa ist nichts weiter als ein ZIP-Archiv mit dem Bundle in einem
# Ordner namens "Payload". Genau das macht dieses Skript.
#
#   Scripts/package-ipa.sh <Pfad/zur/App.app> <Ziel.ipa>
#
set -euo pipefail

APP_PATH="${1:?Pfad zum .app-Bundle fehlt}"
OUTPUT="${2:-TrainAlarm.ipa}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Fehler: ${APP_PATH} existiert nicht." >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

mkdir -p "${WORKDIR}/Payload"
cp -R "${APP_PATH}" "${WORKDIR}/Payload/"

# Sideloading-Werkzeuge signieren selbst neu. Vorhandene (leere) Signaturreste
# wuerden dabei nur stoeren.
rm -rf "${WORKDIR}/Payload/$(basename "${APP_PATH}")/_CodeSignature"

OUTPUT_ABS="$(cd "$(dirname "${OUTPUT}")" && pwd)/$(basename "${OUTPUT}")"
rm -f "${OUTPUT_ABS}"
(cd "${WORKDIR}" && zip -qry "${OUTPUT_ABS}" Payload)

echo "IPA erstellt: ${OUTPUT_ABS}"
ls -lh "${OUTPUT_ABS}"
