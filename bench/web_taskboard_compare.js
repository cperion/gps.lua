const HOST = "127.0.0.1"
const DEFAULT_BASE_PORT = 18000 + Math.floor(Math.random() * 1000) * 3
const PVM_HTTP_PORT = Number(process.env.PVM_HTTP_PORT || DEFAULT_BASE_PORT)
const PVM_WS_PORT = Number(process.env.PVM_WS_PORT || (DEFAULT_BASE_PORT + 1))
const BUN_HTTP_PORT = Number(process.env.BUN_HTTP_PORT || (DEFAULT_BASE_PORT + 2))

const HTTP_WARMUP = Number(process.env.HTTP_WARMUP || 20)
const HTTP_ITERS = Number(process.env.HTTP_ITERS || 120)
const WS_WARMUP = Number(process.env.WS_WARMUP || 12)
const WS_ITERS = Number(process.env.WS_ITERS || 80)

const encoder = new TextEncoder()

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function nowNs() {
  return Bun.nanoseconds()
}

function bytesOf(text) {
  return encoder.encode(String(text)).length
}

function percentile(sorted, p) {
  if (sorted.length === 0) return 0
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.floor(p * sorted.length)))
  return sorted[idx]
}

function summarize(samples, bytes) {
  const sorted = [...samples].sort((a, b) => a - b)
  const total = samples.reduce((a, b) => a + b, 0)
  const totalBytes = bytes.reduce((a, b) => a + b, 0)
  return {
    n: samples.length,
    avgMs: total / samples.length / 1e6,
    p50Ms: percentile(sorted, 0.50) / 1e6,
    p95Ms: percentile(sorted, 0.95) / 1e6,
    minMs: sorted[0] / 1e6,
    maxMs: sorted[sorted.length - 1] / 1e6,
    avgBytes: totalBytes / bytes.length,
  }
}

function fmtMs(x) {
  return x.toFixed(3)
}

function fmtBytes(x) {
  return x.toFixed(1)
}

async function readStream(stream) {
  if (!stream) return ""
  return await new Response(stream).text()
}

async function waitForHttp(url, timeoutMs = 15000) {
  const start = Date.now()
  let lastErr = null
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url)
      if (res.ok || res.status === 404) {
        await res.text()
        return
      }
    } catch (err) {
      lastErr = err
    }
    await sleep(100)
  }
  throw new Error(`timed out waiting for ${url}: ${lastErr || "unknown error"}`)
}

async function spawnServer(kind) {
  if (kind === "pvm") {
    const proc = Bun.spawn({
      cmd: ["luvit", "examples/web_skeleton/server.lua"],
      cwd: process.cwd(),
      env: {
        ...process.env,
        HOST,
        PORT: String(PVM_HTTP_PORT),
        WS_PORT: String(PVM_WS_PORT),
      },
      stdout: "pipe",
      stderr: "pipe",
    })

    try {
      await waitForHttp(`http://${HOST}:${PVM_HTTP_PORT}/__stats`)
    } catch (err) {
      const stderr = await readStream(proc.stderr)
      const stdout = await readStream(proc.stdout)
      proc.kill()
      throw new Error(`failed to start pvm server: ${err}\nstdout:\n${stdout}\nstderr:\n${stderr}`)
    }

    return {
      kind,
      proc,
      httpBase: `http://${HOST}:${PVM_HTTP_PORT}`,
      wsUrl: `ws://${HOST}:${PVM_WS_PORT}/?path=/`,
      wsUrlFor(path) {
        return `ws://${HOST}:${PVM_WS_PORT}/?path=${encodeURIComponent(path)}`
      },
      discardInitialWsMessage: false,
    }
  }

  if (kind === "bun") {
    const proc = Bun.spawn({
      cmd: ["bun", "examples/bun_taskboard/server.js"],
      cwd: process.cwd(),
      env: {
        ...process.env,
        HOST,
        PORT: String(BUN_HTTP_PORT),
      },
      stdout: "pipe",
      stderr: "pipe",
    })

    try {
      await waitForHttp(`http://${HOST}:${BUN_HTTP_PORT}/__stats`)
    } catch (err) {
      const stderr = await readStream(proc.stderr)
      const stdout = await readStream(proc.stdout)
      proc.kill()
      throw new Error(`failed to start bun server: ${err}\nstdout:\n${stdout}\nstderr:\n${stderr}`)
    }

    return {
      kind,
      proc,
      httpBase: `http://${HOST}:${BUN_HTTP_PORT}`,
      wsUrl: `ws://${HOST}:${BUN_HTTP_PORT}/__ws?path=/`,
      wsUrlFor(path) {
        return `ws://${HOST}:${BUN_HTTP_PORT}/__ws?path=${encodeURIComponent(path)}`
      },
      discardInitialWsMessage: true,
    }
  }

  throw new Error(`unknown server kind: ${kind}`)
}

async function stopServer(server) {
  if (!server) return
  try {
    server.proc.kill()
  } catch {}
  try {
    await server.proc.exited
  } catch {}
}

async function benchHttp(baseUrl, path, warmup, iters) {
  const url = `${baseUrl}${path}`
  const opts = {
    headers: {
      Connection: "close",
    },
  }

  for (let i = 0; i < warmup; i++) {
    const res = await fetch(url, opts)
    await res.text()
  }

  const samples = []
  const sizes = []
  for (let i = 0; i < iters; i++) {
    const t0 = nowNs()
    const res = await fetch(url, opts)
    const body = await res.text()
    const dt = nowNs() - t0
    samples.push(dt)
    sizes.push(bytesOf(body))
  }
  return summarize(samples, sizes)
}

function createWsClient(url, discardInitial) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url)
    const queue = []
    let waiters = []

    function push(data) {
      if (waiters.length > 0) {
        const waiter = waiters.shift()
        waiter.resolve(data)
      } else {
        queue.push(data)
      }
    }

    function nextMessage() {
      if (queue.length > 0) {
        return Promise.resolve(queue.shift())
      }
      return new Promise((resolve, reject) => {
        waiters.push({ resolve, reject })
      })
    }

    ws.onerror = (event) => {
      reject(new Error(`websocket error for ${url}: ${event.type}`))
    }

    ws.onmessage = (event) => {
      push(String(event.data))
    }

    ws.onopen = async () => {
      try {
        if (discardInitial) {
          await nextMessage()
        }
        resolve({
          ws,
          nextMessage,
          close() {
            try { ws.close() } catch {}
          },
        })
      } catch (err) {
        reject(err)
      }
    }
  })
}

async function benchWs(url, makeMessage, { warmup, iters, discardInitial }) {
  const client = await createWsClient(url, discardInitial)
  try {
    for (let i = 0; i < warmup; i++) {
      client.ws.send(JSON.stringify(makeMessage(i)))
      await client.nextMessage()
    }

    const samples = []
    const sizes = []
    for (let i = 0; i < iters; i++) {
      const payload = JSON.stringify(makeMessage(i))
      const t0 = nowNs()
      client.ws.send(payload)
      const response = await client.nextMessage()
      const dt = nowNs() - t0
      samples.push(dt)
      sizes.push(bytesOf(response))
    }
    return summarize(samples, sizes)
  } finally {
    client.close()
  }
}

function printSection(title) {
  console.log(`\n${title}`)
  console.log("-".repeat(title.length))
}

function printResultTable(results) {
  console.log("scenario                     impl   avg ms   p50 ms   p95 ms   min ms   max ms   avg bytes")
  console.log("---------------------------  -----  -------  -------  -------  -------  -------  ---------")
  for (const row of results) {
    console.log(
      row.scenario.padEnd(27),
      row.impl.padEnd(5),
      fmtMs(row.stats.avgMs).padStart(8),
      fmtMs(row.stats.p50Ms).padStart(8),
      fmtMs(row.stats.p95Ms).padStart(8),
      fmtMs(row.stats.minMs).padStart(8),
      fmtMs(row.stats.maxMs).padStart(8),
      fmtBytes(row.stats.avgBytes).padStart(10),
    )
  }
}

async function main() {
  const servers = []
  try {
    printSection("starting servers")
    const pvm = await spawnServer("pvm")
    const bun = await spawnServer("bun")
    servers.push(pvm, bun)
    console.log(`pvm http ${pvm.httpBase} ws ${pvm.wsUrl}`)
    console.log(`bun http ${bun.httpBase} ws ${bun.wsUrl}`)

    const results = []

    printSection("http benchmarks")
    for (const server of servers) {
      const home = await benchHttp(server.httpBase, "/", HTTP_WARMUP, HTTP_ITERS)
      results.push({ scenario: "GET /", impl: server.kind, stats: home })
      console.log(`${server.kind} GET / avg ${fmtMs(home.avgMs)} ms`)

      const detail = await benchHttp(server.httpBase, "/task/1", HTTP_WARMUP, HTTP_ITERS)
      results.push({ scenario: "GET /task/1", impl: server.kind, stats: detail })
      console.log(`${server.kind} GET /task/1 avg ${fmtMs(detail.avgMs)} ms`)
    }

    printSection("websocket roundtrip benchmarks")
    for (const server of servers) {
      const localSearch = await benchWs(
        server.wsUrl,
        (i) => ({
          type: "input",
          action: "search",
          target_id: "search",
          value: i % 2 === 0 ? "ship" : "",
        }),
        {
          warmup: WS_WARMUP,
          iters: WS_ITERS,
          discardInitial: server.discardInitialWsMessage,
        },
      )
      results.push({ scenario: "ws local search", impl: server.kind, stats: localSearch })
      console.log(`${server.kind} ws local search avg ${fmtMs(localSearch.avgMs)} ms`)

      const sharedToggle = await benchWs(
        server.wsUrl,
        () => ({
          type: "click",
          action: "toggle-task",
          target_id: "1",
        }),
        {
          warmup: WS_WARMUP,
          iters: WS_ITERS,
          discardInitial: server.discardInitialWsMessage,
        },
      )
      results.push({ scenario: "ws toggle task", impl: server.kind, stats: sharedToggle })
      console.log(`${server.kind} ws toggle task avg ${fmtMs(sharedToggle.avgMs)} ms`)

      const detailTitle = await benchWs(
        server.wsUrlFor("/task/1"),
        (i) => ({
          type: "input",
          action: "task-title",
          target_id: "1",
          value: i % 2 === 0 ? "Ship taskboard demo!" : "Ship taskboard demo",
        }),
        {
          warmup: WS_WARMUP,
          iters: WS_ITERS,
          discardInitial: server.discardInitialWsMessage,
        },
      )
      results.push({ scenario: "ws detail title edit", impl: server.kind, stats: detailTitle })
      console.log(`${server.kind} ws detail title edit avg ${fmtMs(detailTitle.avgMs)} ms`)
    }

    printSection("results")
    printResultTable(results)

    console.log("\nnotes")
    console.log("-----")
    console.log("- pvm = luvit + web/ keyed patch batches")
    console.log("- bun = plain Bun templates + full #app-root replacement")
    console.log("- avg bytes for websocket rows are response payload bytes")
    console.log("- avg bytes for http rows are response body bytes")
  } finally {
    for (const server of servers.reverse()) {
      await stopServer(server)
    }
  }
}

await main()
