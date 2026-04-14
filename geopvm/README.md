# geopvm

GeoPVM v1 skeleton.

Current scope:

- indexed in-memory layers (static grid bbox index)
- bbox query path
- GeoJSON query responses
- GeoJSON Feature / FeatureCollection ingest for POST/PUT writes
- bbox clipping for Point / LineString / Polygon
- quantized debug MVT feature encoder
- tile LRU
- luvit-friendly HTTP handler

HTTP routes currently wired:

- `GET /health`
- `GET /query/{layer}?bbox=minx,miny,maxx,maxy`
- `GET /tiles/{layer}/{z}/{x}/{y}.mvt`
- `POST /features/{layer}`
- `PUT /features/{layer}/{id}`
- `DELETE /features/{layer}/{id}`

Important:

- `geopvm/mvt.lua` is still **not** a real protobuf MVT encoder; it emits deterministic tile-local debug records with quantized coordinates
- `geopvm/clip.lua` now does bbox clipping for Point / LineString / Polygon, but still has v1 limitations (e.g. no Multi* geometries, longest-visible-run fallback for complex re-entering lines)
- `geopvm/store.lua` is still memory-backed, but bbox queries now use a simple static grid index; FlatGeobuf mmap/packed-index integration is next
- GeoJSON ingest currently accepts Point / LineString / Polygon with flat scalar properties and leaves coordinates unchanged
