#!/usr/bin/env bash
# Fetch real reference photos for deep-sky objects from Wikipedia's page-image
# API (mostly NASA/ESA public-domain or CC lead images) into the app bundle.
#
#   bash Scripts/fetch_object_images.sh
#
# Output: AstroSky/ObjectImages/<objectID>.jpg  (e.g. m087.jpg, ngc253.jpg)
# Planets reuse the bundled 2K textures, so only deep-sky objects are fetched.
# Attribution: images courtesy of Wikimedia Commons contributors / NASA / ESA.

set -uo pipefail
cd "$(dirname "$0")/.."
OUT="AstroSky/ObjectImages"
mkdir -p "$OUT"
UA="AstroSky/1.0 (personal astronomy app; brian@innjoybnb.com)"
SIZE=800
ok=0; miss=0

fetch() {
  local id="$1" title="$2"
  local dest="$OUT/$id.jpg"
  [ -s "$dest" ] && { echo "skip $id (exists)"; ok=$((ok+1)); return; }
  # The REST summary endpoint returns the pre-existing full image file
  # (reliably served, unlike the on-demand thumbnail API which gets
  # rate-limited to HTML error pages). We downsample locally with sips.
  local url
  url=$(curl -sL --max-time 25 -A "$UA" "https://en.wikipedia.org/api/rest_v1/page/summary/$title" \
    | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('originalimage',{}).get('source') or d.get('thumbnail',{}).get('source') or '')
except Exception:
    print('')" 2>/dev/null)
  if [ -z "$url" ]; then echo "MISS $id ($title): no image"; miss=$((miss+1)); return; fi
  local tmp; tmp=$(mktemp)
  if curl -sL --max-time 90 -A "$UA" -o "$tmp" "$url" && [ "$(wc -c < "$tmp")" -gt 4000 ]; then
    if sips -s format jpeg -Z "$SIZE" "$tmp" --out "$dest" >/dev/null 2>&1 && [ -s "$dest" ]; then
      echo "ok   $id  <- $title"; ok=$((ok+1))
    else
      echo "FAIL $id ($title): resize error"; rm -f "$dest"; miss=$((miss+1))
    fi
  else
    echo "BAD  $id ($title): bad download"; miss=$((miss+1))
  fi
  rm -f "$tmp"
  sleep 0.3
}

# Messier 1–110 — deterministic Wikipedia titles.
for n in $(seq 1 110); do
  fetch "$(printf 'm%03d' "$n")" "Messier_$n"
done

# NGC highlights carried in the app catalog.
for num in 253 891 4565 4631 7000 869 2244; do
  fetch "ngc$num" "NGC_$num"
done

echo "----"
echo "Fetched $ok, missing $miss into $OUT"
