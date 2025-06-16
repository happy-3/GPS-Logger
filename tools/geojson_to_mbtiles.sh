#!/bin/bash
# Convert GeoJSON files to MBTiles vector format using tippecanoe.
# Usage: ./geojson_to_mbtiles.sh file1.geojson [file2.geojson ...]
set -e
if ! command -v tippecanoe >/dev/null; then
  echo "tippecanoe is required" >&2
  exit 1
fi
for f in "$@"; do
  base="${f%.geojson}"
  tippecanoe -zg -o "${base}.mbtiles" "$f"
  echo "Created ${base}.mbtiles"
done
