#!/usr/bin/env bash
# Rasterise every help SVG in this folder to assets/graphics/help/<name>.png
# Run from anywhere; needs inkscape.
set -e
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/../graphics/help"
mkdir -p "$out"
for f in "$here"/*.svg; do
  n="$(basename "${f%.svg}")"
  inkscape "$f" --export-type=png --export-filename="$out/$n.png" --export-width=1280 >/dev/null 2>&1
  echo "  $n.png"
done
