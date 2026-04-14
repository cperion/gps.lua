# GeoPVM v1 — Design Specification (Rewritten)

## 1) Purpose

GeoPVM is an embedded **vector-only** spatial runtime for LuaJIT:

- input: FlatGeobuf datasets + optional in-memory edits
- output: tile bytes (MVT first), plus query endpoints
- runtime: one process, luvit HTTP/event loop

It targets the common app-backend case where the working set fits in RAM and low-latency serving matters more than SQL completeness.

---

## 2) Non-Goals

GeoPVM v1 is **not**:

- a general SQL database
- a raster engine
- a multi-writer transactional datastore
- a distributed/replicated system

Use PostGIS/GDAL/Titiler for those domains.

---

## 3) Core Architecture

Three libraries, one process:

- `pvm` — ASDL types + phase boundaries + structural reuse
- `quote` — generated decoders/encoders from schemas
- `luvit` — HTTP + async I/O

Design rule:

- Use **pvm phases** for semantic transforms and reusable compute.
- Keep packed R-tree walking as **raw FFI numeric traversal** (not phase-wrapped).
- Use explicit bounded LRUs for unbounded request-space caches.

---

## 4) Runtime Constraints (Important)

### 4.1 ASDL syntax in this repo

This codebase expects parser syntax like:

- field form: `number x` (not `x: number`)
- product form: `Type = (number x, string y)`
- builtin scalar types: `number`, `string`, `boolean`, etc.

If `int` is desired, register it with `ctx:Extern("int", check_fn)`.

### 4.2 Interning behavior

`unique` nodes are interned by strong tries in `asdl_context.lua`.

Implications:

- `unique` gives identity reuse and cache hits.
- do **not** mark unbounded request keys as `unique`.
- weak decode maps alone do not guarantee memory release if returned nodes are strongly interned forever.

### 4.3 pvm cache behavior

Phase caches are weak-keyed by source node identity. This is powerful for long-lived structural nodes, but request-space caching still needs explicit policy/LRU.

---

## 5) Data Model (v1)

### 5.1 Source/identity types (bounded, interned)

```lua
local G = pvm.context():Define [[
module Geo {
  Coord = (number x, number y) unique
  Ring  = (Coord* coords) unique
  BBox  = (number minx, number miny, number maxx, number maxy) unique

  Geometry = Point(number x, number y) unique
           | LineString(Coord* coords) unique
           | Polygon(Ring* rings) unique

  PropValue = PStr(string v) unique
            | PNum(number v) unique
            | PBool(boolean v) unique
            | PNull unique

  Prop  = (string key, PropValue value) unique
  Props = (Prop* entries) unique

  Feature    = (string id, Geometry geom, Props props) unique
  LayerMeta  = (string name, number srid) unique

  -- revisioned identity used in cache keys/invalidation
  LayerRef   = (LayerMeta meta, number rev) unique
}
]]
```

### 5.2 Request/transient types (not interned)

Do not mark high-cardinality external inputs as `unique`.

```lua
local Q = pvm.context():Define [[
module Query {
  TileReq = (string layer, number z, number x, number y, string fmt)
  BBoxReq = (string layer, number minx, number miny, number maxx, number maxy)
}
]]
```

### 5.3 Derived types

- Static index entries are offsets in FlatGeobuf (FFI-level data).
- Dynamic edit index may use ASDL (`RNode`, `REntry`) if needed for structural updates.
- Final execution stream should use one flat command/product type + singleton kind tags.

---

## 6) Storage

### 6.1 Canonical format

FlatGeobuf on disk.

At open:

1. mmap file
2. read packed Hilbert R-tree metadata
3. prepare schema-specialized decode function(s) via `quote`

### 6.2 Decode strategy

- Packed R-tree yields candidate offsets.
- Decode per offset lazily.
- Keep decode cache as bounded LRU by offset (not unbounded table).

If decoded nodes are interned (`unique Feature`), memory lifetime must be monitored. For v1, enforce dataset/working-set bounds and expose memory telemetry.

### 6.3 Write strategy

- Maintain in-memory edit overlay (insert/update/delete)
- Reads merge: static mmap + edit overlay
- Periodic snapshot flush: write new FlatGeobuf temp, fsync, atomic rename

No WAL in v1.

---

## 7) Query and Tile Pipeline

## 7.1 Canonical flow

```
HTTP -> parse -> normalize request
     -> tile LRU lookup
     -> query candidates (FFI R-tree)
     -> lazy decode features
     -> clip phase
     -> encode_mvt phase
     -> tile assemble -> HTTP bytes
```

v1 scope: MVT first. GeoJSON/WKB later.

### 7.2 pvm boundaries (v1)

Recommended boundaries:

1. `normalize_request` (scalar boundary)
2. `clip` (streaming phase)
3. `encode_mvt_feature` (streaming phase)
4. `assemble_tile` (scalar boundary from encoded stream)

The static R-tree walk remains a plain function.

### 7.3 Handler contract reminder

Every `pvm.phase` handler must return a **triplet** (`pvm.once`, `pvm.children`, `pvm.concat*`, etc.), never a raw value.

---

## 8) Cache Model and Invalidation

### 8.1 Two cache classes

1. **Identity caches** (inside pvm phases):
   - keyed by ASDL node identity
   - excellent for stable structural subgraphs

2. **Request-space LRUs** (explicit maps):
   - tile bytes LRU by string key: `layer@rev|fmt|z/x/y|styleRev`
   - decode LRU by feature offset (and dataset revision)

### 8.2 Revision discipline

All externally visible read artifacts must include revision in their key.

On write flush:

- bump `layer.rev`
- old keys naturally miss
- no global sweep needed for correctness

---

## 9) HTTP API (v1)

### Required

- `GET /tiles/{layer}/{z}/{x}/{y}.mvt`
- `GET /query/{layer}?bbox=minx,miny,maxx,maxy`
- `POST /features/{layer}`
- `PUT /features/{layer}/{id}`
- `DELETE /features/{layer}/{id}`
- `GET /health`

### Optional (v1.1+)

- GeoJSON/WKB tile endpoints
- radius queries
- layer upload/create endpoints

---

## 10) Observability and Success Metrics

Expose `/health` with:

- pvm phase reports (`pvm.report_string`) for core boundaries
- tile LRU hit/miss/eviction counts
- decode LRU hit/miss counts
- live decoded feature count estimate
- process RSS

Target ranges (initial):

- warm tile p50 < 0.5ms
- warm tile p95 < 2ms
- core phase reuse > 90% on pan/zoom traces

---

## 11) Implementation Plan (6 weeks)

### Week 1 — FlatGeobuf Reader

- mmap wrapper + packed R-tree walker (FFI)
- schema parse + quote-generated decoder
- decode LRU and metrics

### Week 2 — Query Engine

- bbox query path (offsets -> lazy decode -> stream)
- merge static + edit overlay reads
- benchmark cold/warm query latency

### Week 3 — Tile v1 (MVT)

- clip phase
- mvt feature encoder phase
- tile assemble + tile LRU

### Week 4 — HTTP Integration

- luvit routes
- end-to-end tile/query serving
- `/health` + metrics + phase reports

### Week 5 — Write Path

- insert/update/delete overlay
- revision bump and invalidation discipline
- snapshot flush (temp + fsync + rename)

### Week 6 — Hardening

- input validation + limits
- load test, profiling, memory tuning
- failure-path tests for flush/restart

---

## 12) v1 Acceptance Criteria

1. MVT tiles served from single process with no external cache
2. Warm tile requests dominated by cache hits (pvm + tile LRU)
3. Single-feature edit invalidates only affected revision keys
4. Startup for medium dataset (<100k features) under 100ms target
5. Operational memory remains bounded by configured LRUs + active interned graph
6. Clear documented limits: single writer, vector-only, memory-bound

---

## 13) Design Rules (Do/Don’t)

### Do

- use `unique` for bounded, reusable structural nodes
- keep request keys non-unique
- include revision/style/format in tile cache keys
- keep packed-index traversal outside phase boundaries
- monitor reuse ratio and LRU metrics continuously

### Don’t

- don’t assume weak Lua tables alone bound memory with strong interning
- don’t return raw values from phase handlers
- don’t mutate interned nodes (use `pvm.with`)
- don’t cache tile bytes without revision-aware keys

---

This document is the baseline GeoPVM v1 plan for this repository/runtime.
