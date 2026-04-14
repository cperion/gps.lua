# Web taskboard comparison

This benchmark compares:

- `examples/web_skeleton/server.lua` — pvm/web on **Luvit** with keyed live patches
- `examples/bun_taskboard/server.js` — plain **Bun** templates with full fragment replacement

## Run

```bash
bun bench/web_taskboard_compare.js
```

Optional knobs:

```bash
HTTP_WARMUP=20 HTTP_ITERS=120 WS_WARMUP=12 WS_ITERS=80 bun bench/web_taskboard_compare.js
```

By default the benchmark picks fresh local ports to avoid collisions with already-running demos.

Ports can also be overridden:

```bash
PVM_HTTP_PORT=8180 PVM_WS_PORT=8181 BUN_HTTP_PORT=9191 bun bench/web_taskboard_compare.js
```

## What it measures

HTTP:

- `GET /`
- `GET /task/1`

WebSocket roundtrips:

- local search input on `/`
- shared task toggle on `/`
- detail title edit on `/task/1`

For websocket rows, the benchmark also reports average response payload size.

## Notes

- The HTTP client forces `Connection: close` to avoid keep-alive timing artifacts between Bun's client and the Luvit server.
- The Bun app is intentionally a realistic baseline: plain object state + template strings + full `#app-root` replacement.
- The pvm app uses structural HTML, keyed diffing, and patch batches.

## Sample result on this machine

```text
scenario                     impl   avg ms   p50 ms   p95 ms   min ms   max ms   avg bytes
---------------------------  -----  -------  -------  -------  -------  -------  ---------
GET /                       pvm      1.383    1.234    2.316    1.024    5.957     8252.0
GET /task/1                 pvm      1.083    1.001    1.902    0.811    2.643     5695.0
GET /                       bun      0.136    0.120    0.227    0.089    0.442     7199.0
GET /task/1                 bun      0.130    0.108    0.230    0.086    0.499     4874.0
ws local search             pvm      0.130    0.117    0.250    0.058    0.428     1311.5
ws toggle task              pvm      0.185    0.160    0.356    0.118    0.579     1351.0
ws detail title edit        pvm      0.082    0.080    0.116    0.058    0.237      427.5
ws local search             bun      0.046    0.040    0.067    0.031    0.334     6469.5
ws toggle task              bun      0.055    0.047    0.099    0.038    0.160     7390.0
ws detail title edit        bun      0.049    0.042    0.073    0.034    0.514     4863.5
```

Interpretation:

- Bun wins clearly on raw latency in this comparison.
- pvm/web sends much smaller payloads for some live updates (`search`, `toggle`).
- pvm/web still loses on raw latency here, but much less badly on live edits than before.
- moving CSS/client JS out of the HTML body brought the pvm page size much closer to the Bun baseline.
- flattening the task grid into directly keyed children turned task toggle updates into tiny attr/text patches instead of subtree replacement.
- after keying the document head/title/style shell, `ws detail title edit` dropped from a full-page replace to a few tiny patch ops.
