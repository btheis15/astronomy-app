#!/bin/bash
#
# fetch_hyg.sh — download the HYG star database, trim it to the naked-eye stars
# the app needs, and write AstroSky/hygdata.csv (auto-picked up by
# HYGCatalogLoader; the app works fine without it).
#
# Usage:  Scripts/fetch_hyg.sh
#
# Data: HYG database by David Nash / astronexus, CC BY-SA 4.0
#       https://github.com/astronexus/HYG-Database
#
# Output columns match HYGCatalogLoader's expectations: id,proper,ra,dec,dist,mag,ci,con
# Rows are limited to magnitude <= 6.5 (~9,000 stars, a few hundred KB).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_ROOT/AstroSky/hygdata.csv"
MAG_LIMIT="${1:-6.5}"

# HYG v4.1 (update this URL if the HYG layout changes).
URL="https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Downloading HYG database…"
curl -fSL "$URL" -o "$TMP"

echo "Trimming to magnitude <= $MAG_LIMIT and projecting columns…"
awk -F',' -v maglimit="$MAG_LIMIT" '
NR == 1 {
    for (i = 1; i <= NF; i++) { col[$i] = i }
    print "id,proper,ra,dec,dist,mag,ci,con"
    next
}
{
    mag = $(col["mag"]) + 0
    if (mag == "" || mag > maglimit) next
    printf "%s,%s,%s,%s,%s,%s,%s,%s\n", \
        $(col["id"]), $(col["proper"]), $(col["ra"]), $(col["dec"]), \
        $(col["dist"]), $(col["mag"]), $(col["ci"]), $(col["con"])
}
' "$TMP" > "$OUT"

COUNT="$(($(wc -l < "$OUT") - 1))"
echo "Wrote $OUT ($COUNT stars). Rebuild in Xcode to see the deep sky."
