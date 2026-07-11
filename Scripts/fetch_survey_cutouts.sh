#!/usr/bin/env bash
# Fetch wide-field survey cutouts (what an object actually looks like framed to
# its real angular size — the "telescope view") from CDS hips2fits: Pan-STARRS
# color north of dec -28, DSS2 color further south. Reads Scripts/deepsky_coords.csv
# (id,raDeg,decDeg,sizeArcmin) dumped from the app catalog.
#
#   bash Scripts/fetch_survey_cutouts.sh
#
# Output: AstroSky/ObjectImages/<id>_wide.jpg

set -uo pipefail
cd "$(dirname "$0")/.."
OUT="AstroSky/ObjectImages"; mkdir -p "$OUT"
CSV="Scripts/deepsky_coords.csv"
UA="AstroSky/1.0 (personal astronomy app; brian@innjoybnb.com)"
ok=0; miss=0

while IFS=, read -r id ra dec arcmin; do
  [ -z "$id" ] && continue
  dest="$OUT/${id}_wide.jpg"
  [ -s "$dest" ] && { ok=$((ok+1)); continue; }
  # Field of view framed to ~2.2x the object, clamped for sanity.
  fov=$(python3 -c "s=$arcmin/60.0*2.2; print(round(min(4.0,max(0.12,s)),4))")
  hips=$(python3 -c "print('CDS/P/PanSTARRS/DR1/color-z-zg-g' if $dec>=-28 else 'CDS/P/DSS2/color')")
  hipsenc=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$hips',safe=''))")
  url="https://alasky.u-strasbg.fr/hips-image-services/hips2fits?hips=${hipsenc}&ra=${ra}&dec=${dec}&fov=${fov}&width=1000&height=1000&format=jpg"
  tmp=$(mktemp)
  if curl -sL --max-time 90 -A "$UA" -o "$tmp" "$url" \
     && [ "$(wc -c < "$tmp")" -gt 3000 ] && file "$tmp" | grep -qi "JPEG"; then
    mv "$tmp" "$dest"; echo "ok   ${id}_wide  fov=${fov}°"; ok=$((ok+1))
  else
    echo "MISS $id (fov ${fov}°)"; rm -f "$tmp"; miss=$((miss+1))
  fi
  sleep 0.3
done < "$CSV"

echo "----"
echo "Survey cutouts: $ok ok, $miss miss"
