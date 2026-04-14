# bun_taskboard

A realistic Bun baseline for comparing against `examples/web_skeleton/`.

## What this is

This app intentionally uses a more typical Bun/server-template shape:

- plain JavaScript objects for state
- template strings for SSR
- `Bun.serve`
- websocket messages from a tiny browser helper
- full `#app-root` fragment replacement on updates

## What this is *not*

It is **not** a hand-optimized structural AST + diff engine.
That would be a different comparison.

The point of this example is to approximate what a competent normal developer
might actually build in Bun for the same taskboard.

## Routes

- `/` — board
- `/task/:id` — task detail
- `/__stats` — simple server stats

## Run

```bash
bun examples/bun_taskboard/server.js
```

Default port:

- `9090`

Override with:

```bash
PORT=9090 bun examples/bun_taskboard/server.js
```

## Comparison target

Compare against:

```bash
luajit examples/web_skeleton/server.lua
```

That pvm/web version uses:

- ASDL values
- pvm phases
- keyed live diff
- patch batches over websocket
- tiny browser patch applicator

This Bun version uses:

- plain object state
- full fragment rerender + replace

So the comparison is intentionally about **default architecture**, not just raw engine speed.
