#!/usr/bin/env bash
# Fetch the beautiful public-domain Hubble images from NASA's official Hubble
# Messier Catalog and bundle them as the app's Messier photos.
#   https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/
#
#   bash Scripts/fetch_hubble_messier.sh
#
# Output: overwrites AstroSky/ObjectImages/mNNN.jpg with the Hubble image
# (downloaded, then downsampled to <=1000px jpg via sips). Objects not in the
# Hubble catalog keep their existing survey/reference image.

set -uo pipefail
cd "$(dirname "$0")/.."
OUT="AstroSky/ObjectImages"; mkdir -p "$OUT"
UA="AstroSky/1.0 (personal astronomy app; brian@innjoybnb.com)"
SIZE=1000
ok=0; miss=0

# num|url  (dynamicimage URLs get ?w=1600 to bound download size)
MAP="
1|https://science.nasa.gov/wp-content/uploads/2023/04/crab-nebula-mosaic-jpg.webp
2|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M2_potw1913a.jpg?w=1600
3|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M3_2019_potw1914a.jpg?w=1600
4|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M4_WFC3_ACS_ok_flat_cont_FINAL_NewImage.jpg?w=1600
5|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M5_WFC3_UV_flat_FINAL_NewImage.jpg?w=1600
7|https://science.nasa.gov/wp-content/uploads/2023/06/hubble-m7-wfc3-2-flat-final-jpg.webp
8|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/nebulae/emission/Hubble_M8_ACS_1_flat_FINAL.jpg?w=1600
9|https://science.nasa.gov/wp-content/uploads/2023/04/heic1205a-jpg.webp
10|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M10_WFC3UVIS_flat_FINAL_NewImage.jpg?w=1600
11|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/open-clusters/Hubble_M11_2019_potw1912a.jpg?w=1600
12|https://science.nasa.gov/wp-content/uploads/2023/04/potw1113a-jpg.webp
13|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M13_2010_potw1011a.jpg?w=1600
14|https://science.nasa.gov/wp-content/uploads/2023/04/hubble_m14_wfc3_1flat_cont_final-jpg.webp
15|https://science.nasa.gov/wp-content/uploads/2023/04/heic1321a-jpg.webp
16|https://science.nasa.gov/wp-content/uploads/2023/04/hubble_birthofstars_0-jpg.webp
17|https://science.nasa.gov/wp-content/uploads/2017/10/m17-field2-f110wf160w-a1-final-vers1.jpg
19|https://science.nasa.gov/wp-content/uploads/2023/04/hubble_m19_wfc3_str_gapfilled_flat_cont_final-jpg.webp
20|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/nebulae/emission/hubble_2026_trifid.jpg?w=1600
22|https://science.nasa.gov/wp-content/uploads/2023/04/potw1514a-jpg.webp
24|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/star-cloud/Hubble_M24_1_flat_FINAL_B_rot90.jpg?w=1600
27|https://science.nasa.gov/wp-content/uploads/2023/04/opo0306a-jpg.webp
28|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M28_potw1910a.tif?w=1600
30|https://science.nasa.gov/wp-content/uploads/2023/04/heic0918a-jpg.webp
31|https://science.nasa.gov/wp-content/uploads/2023/04/hs-2015-02-a-hires_jpg-jpg.webp
32|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/elliptical/Hubble_M32_str2_flat_FINAL_NewImage.jpg?w=1600
33|https://science.nasa.gov/wp-content/uploads/2023/04/heic1901a-jpg.webp
35|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/open-clusters/Hubble_M35_WFPC2ok_flat_FINAL1.jpg?w=1600
42|https://science.nasa.gov/wp-content/uploads/2023/04/orion-nebula-xlarge_web-jpg.webp
43|https://science.nasa.gov/wp-content/uploads/2023/04/heic0601c-jpg.webp
44|https://science.nasa.gov/wp-content/uploads/2024/08/m44-acs-1-color-2-final-sm.jpg
45|https://science.nasa.gov/wp-content/uploads/2023/04/interstellar_cloud_in_pleiades-jpg.webp
46|https://science.nasa.gov/wp-content/uploads/2023/04/hubble_ngc2438_wfpc2_screen_3mb.png
48|https://science.nasa.gov/wp-content/uploads/2024/08/hubble-m48-1-flat-final-2.jpg
49|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/elliptical/Hubble_M49_potw1911a.tif?w=1600
51|https://science.nasa.gov/wp-content/uploads/2023/04/m51-and-companion_0-jpg.webp
53|https://science.nasa.gov/wp-content/uploads/2023/04/potw1140a-jpg.webp
54|https://science.nasa.gov/wp-content/uploads/2023/04/potw1145a-jpg.webp
55|https://science.nasa.gov/wp-content/uploads/2023/06/hubble-m55-mos-acs-long-flat-final2-jpg.webp
56|https://science.nasa.gov/wp-content/uploads/2023/04/potw1234a-jpg.webp
57|https://science.nasa.gov/wp-content/uploads/2023/04/ring-nebula-full_jpg-jpg.webp
58|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_M58_1_flat_FINAL_NewImage.jpg?w=1600
59|https://science.nasa.gov/wp-content/uploads/2023/04/potw1921a-jpg.webp
60|https://science.nasa.gov/wp-content/uploads/2023/04/m60_and_ngc_4647-jpg.webp
61|https://science.nasa.gov/wp-content/uploads/2023/04/potw1324a-jpg.webp
62|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M62_2019_potw1915a.jpg?w=1600
63|https://science.nasa.gov/wp-content/uploads/2023/04/potw1536a-jpg.webp
64|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_Webb_M64_UVIS_V4_flat_FINAL_NewImage.jpg?w=1600
65|https://science.nasa.gov/wp-content/uploads/2023/04/potw1352a-1-jpg.webp
66|https://science.nasa.gov/wp-content/uploads/2023/04/heic1006a-jpg.webp
67|https://science.nasa.gov/wp-content/uploads/2024/08/m67-acs-1mstr-flat-final-sm.jpg
68|https://science.nasa.gov/wp-content/uploads/2023/04/potw1231a-jpg.webp
69|https://science.nasa.gov/wp-content/uploads/2023/04/potw1240a-jpg.webp
70|https://science.nasa.gov/wp-content/uploads/2023/04/potw1215a-jpg.webp
71|https://science.nasa.gov/wp-content/uploads/2023/04/potw1018a-jpg.webp
72|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M72_potw2516a.tif?w=1600
74|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_M74_2022_potw2235a.jpg?w=1600
75|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/stars/globular-clusters/Hubble_M75_2019_potw1916a.jpg?w=1600
76|https://science.nasa.gov/wp-content/uploads/2024/04/hubble-34th-littledumbell-sm-stsci-01htddrc7nr68q120setwhmsaq.png
77|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_M77_2025_potw2515a.jpg?w=1600
78|https://science.nasa.gov/wp-content/uploads/2023/04/m78_0-jpg.webp
79|https://science.nasa.gov/wp-content/uploads/2023/04/m791343x1343.png
80|https://science.nasa.gov/wp-content/uploads/2023/04/hubble_m80_wfc3_acs_comb_final2-jpg.webp
81|https://science.nasa.gov/wp-content/uploads/2023/04/m81-print-jpg.webp
82|https://science.nasa.gov/wp-content/uploads/2023/04/m82-jpg.webp
83|https://science.nasa.gov/wp-content/uploads/2023/04/m83-jpg.webp
84|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/elliptical/M84_1_core2_flat_FINAL3.jpg?w=1600
85|https://science.nasa.gov/wp-content/uploads/2023/04/m85_0-jpg.webp
86|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/Hubble_M86_2019_potw1938a.jpg?w=1600
87|https://science.nasa.gov/wp-content/uploads/2023/04/m87-full_jpg-jpg.webp
88|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_M88_PTOM_NewImage.jpg?w=1600
89|https://science.nasa.gov/wp-content/uploads/2023/04/m89.png
90|https://science.nasa.gov/wp-content/uploads/2024/10/hubble-m90-potw2442a.jpg
91|https://science.nasa.gov/wp-content/uploads/2023/04/m91_wfc3_4_crop_v2_final-jpg.webp
92|https://science.nasa.gov/wp-content/uploads/2023/04/potw1449a_0-jpg.webp
94|https://science.nasa.gov/wp-content/uploads/2023/04/hubble_friday_102315-jpg.webp
95|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_M95_center_ma_flat_FINAL_NewImage.jpg?w=1600
96|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/Hubble_M96_2025_potw2534a.jpg?w=1600
98|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/Hubble_M98_potw1925a.tif?w=1600
99|https://science.nasa.gov/wp-content/uploads/2023/04/potw1223a-jpg.webp
100|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/releases/2018/12/STScI-01EVSYX5KXKD5N7E53PYXGQ5E4.tif?w=1600
101|https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/galaxies/spiral/M101_HST_MIRI_V3_flat_FINAL_NewImage.jpg?w=1600
102|https://science.nasa.gov/wp-content/uploads/2023/04/ngc5866-jpg.webp
104|https://science.nasa.gov/wp-content/uploads/2023/04/sombrero-galaxy-hubble-jpg.webp
105|https://science.nasa.gov/wp-content/uploads/2023/04/m105-jpg.webp
106|https://science.nasa.gov/wp-content/uploads/2023/04/m106-1-jpg.webp
107|https://science.nasa.gov/wp-content/uploads/2023/04/potw1229a-jpg.webp
108|https://science.nasa.gov/wp-content/uploads/2018/03/hubble-m108-1-flat-final-new.jpg
109|https://science.nasa.gov/wp-content/uploads/2023/06/hubble-m109-wfc3-2flat-jpg.webp
110|https://science.nasa.gov/wp-content/uploads/2023/04/m110.png
"

while IFS='|' read -r num url; do
  [ -z "$num" ] && continue
  id=$(printf 'm%03d' "$num")
  dest="$OUT/$id.jpg"
  tmp=$(mktemp)
  if curl -sL --max-time 120 -A "$UA" -o "$tmp" "$url" && [ "$(wc -c < "$tmp")" -gt 4000 ]; then
    if sips -s format jpeg -Z "$SIZE" "$tmp" --out "$dest" >/dev/null 2>&1 && [ -s "$dest" ]; then
      echo "ok   $id  (Hubble)"; ok=$((ok+1))
    else
      echo "FAIL $id: resize error"; miss=$((miss+1))
    fi
  else
    echo "BAD  $id: download error ($url)"; miss=$((miss+1))
  fi
  rm -f "$tmp"
  sleep 0.25
done <<< "$MAP"

echo "----"
echo "Hubble Messier images: $ok ok, $miss failed"
