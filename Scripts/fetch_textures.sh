#!/bin/bash
#
# fetch_textures.sh — download real 2K planet/Sun/Moon/ring/Milky-Way texture
# maps for the Scale AR feature and place them in AstroSky/Textures/.
#
# Source: Solar System Scope (https://www.solarsystemscope.com/textures/),
#         Creative Commons Attribution 4.0 (CC BY 4.0). Attribution is shown in
#         the app's Settings ▸ About. Downloaded via the Wikimedia Commons
#         mirror, which exposes stable direct URLs.
#
# Usage:  bash Scripts/fetch_textures.sh
#
# The app renders with procedural textures until these files are present, and
# for the small moons the set doesn't cover — so this step is optional.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(cd "$SCRIPT_DIR/.." && pwd)/AstroSky/Textures"
mkdir -p "$OUT"

# Files to fetch (Solar System Scope names, as mirrored on Wikimedia Commons).
FILES=(
  "2k_sun.jpg"
  "2k_mercury.jpg"
  "2k_venus_atmosphere.jpg"
  "2k_earth_daymap.jpg"
  "2k_mars.jpg"
  "2k_jupiter.jpg"
  "2k_saturn.jpg"
  "2k_saturn_ring_alpha.png"
  "2k_uranus.jpg"
  "2k_neptune.jpg"
  "2k_moon.jpg"
  "2k_stars_milky_way.jpg"
)

BASE="https://commons.wikimedia.org/wiki/Special:FilePath/Solarsystemscope_texture_"
# Wikimedia requires a descriptive User-Agent and rate-limits rapid requests.
UA="AstroSky/1.0 (https://github.com/btheis15/astronomy-app; brian@innjoybnb.com)"

for file in "${FILES[@]}"; do
  [ -s "$OUT/$file" ] && { echo "Have $file"; continue; }
  echo "Fetching $file…"
  if curl -fsSL -A "$UA" "${BASE}${file}" -o "$OUT/$file"; then
    echo "  → $OUT/$file"
  else
    rm -f "$OUT/$file"
    echo "  (skipped $file — procedural fallback will be used)"
  fi
  sleep 2
done

echo "Done. Rebuild in Xcode to see the real textures in the Explore tab."
