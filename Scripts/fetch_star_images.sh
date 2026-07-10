#!/usr/bin/env bash
# Fetch real photos for famous named stars from Wikipedia's page-image API into
# the app bundle. Uses a curated key|WikipediaTitle list so ambiguous common
# names (Peacock, Mimosa, …) resolve to the correct star, not a bird or plant.
#
#   bash Scripts/fetch_star_images.sh
#
# Output: AstroSky/ObjectImages/star_<catalogKey>.jpg  (matches ObjectImagery)

set -uo pipefail
cd "$(dirname "$0")/.."
OUT="AstroSky/ObjectImages"; mkdir -p "$OUT"
UA="AstroSky/1.0 (personal astronomy app; brian@innjoybnb.com)"
SIZE=600
ok=0; miss=0

# key|Wikipedia title. Ambiguous proper names use the Bayer designation.
STARS="
sirius|Sirius
canopus|Canopus
arcturus|Arcturus
vega|Vega
capella|Capella
rigel|Rigel
procyon|Procyon
betelgeuse|Betelgeuse
achernar|Achernar
altair|Altair
aldebaran|Aldebaran
antares|Antares
spica|Spica
pollux|Pollux
fomalhaut|Fomalhaut
deneb|Deneb
regulus|Regulus
castor|Castor
bellatrix|Bellatrix
alnilam|Alnilam
alnitak|Alnitak
mintaka|Mintaka
saiph|Saiph
adhara|Adhara
mirzam|Mirzam
wezen|Wezen
alioth|Alioth
dubhe|Dubhe
alkaid|Alkaid
mizar|Mizar
merak|Merak
polaris|Polaris
kochab|Kochab
algol|Algol
mirfak|Mirfak
denebola|Denebola
alphard|Alphard
acrux|Acrux
gacrux|Gacrux
mimosa|Beta_Crucis
hadar|Beta_Centauri
shaula|Shaula
elnath|Elnath
alhena|Alhena
schedar|Schedar
caph|Caph
rasalhague|Rasalhague
eltanin|Eltanin
hamal|Hamal
mirach|Mirach
alpheratz|Alpheratz
almach|Almach
enif|Enif
sadr|Gamma_Cygni
nunki|Nunki
peacock|Alpha_Pavonis
naos|Zeta_Puppis
regor|Gamma_Velorum
diphda|Beta_Ceti
izar|Epsilon_Bootis
dschubba|Delta_Scorpii
menkalinan|Menkalinan
algieba|Algieba
"

while IFS='|' read -r key title; do
  [ -z "$key" ] && continue
  dest="$OUT/star_$key.jpg"
  [ -s "$dest" ] && { echo "skip $key"; ok=$((ok+1)); continue; }
  url=$(curl -sL --max-time 25 -A "$UA" \
    "https://en.wikipedia.org/w/api.php?action=query&format=json&redirects=1&prop=pageimages&piprop=thumbnail&pithumbsize=$SIZE&titles=$title" \
    | python3 -c "import sys,json
try:
    d=json.load(sys.stdin); p=d['query']['pages']
    print(next(iter(p.values())).get('thumbnail',{}).get('source',''))
except Exception:
    print('')" 2>/dev/null)
  if [ -z "$url" ]; then echo "MISS $key ($title)"; miss=$((miss+1)); continue; fi
  if curl -sL --max-time 40 -A "$UA" -o "$dest" "$url" && [ -s "$dest" ]; then
    echo "ok   star_$key <- $title"; ok=$((ok+1))
  else
    echo "FAIL $key"; rm -f "$dest"; miss=$((miss+1))
  fi
done <<< "$STARS"

echo "----"
echo "Stars fetched $ok, missing $miss"
