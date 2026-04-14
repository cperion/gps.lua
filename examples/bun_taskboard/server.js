import { applyClientMessage, initialState, normalizeUi, pageTitle, renderAppRoot, renderPage, statsText } from "./app.js"

const HOST = process.env.HOST || "127.0.0.1"
const PORT = Number(process.env.PORT || 9090)

let state = initialState()
const connections = new Set()

function renderMessage(ws) {
  return JSON.stringify({
    title: pageTitle(state, ws.data.path),
    html: renderAppRoot({ state, path: ws.data.path, ui: ws.data.ui }),
  })
}

function refresh(ws) {
  ws.send(renderMessage(ws))
}

function broadcast() {
  for (const ws of connections) {
    refresh(ws)
  }
}

const server = Bun.serve({
  hostname: HOST,
  port: PORT,

  fetch(req, server) {
    const url = new URL(req.url)

    if (url.pathname === "/client.js") {
      return new Response(Bun.file(new URL("./client.js", import.meta.url)), {
        headers: { "Content-Type": "application/javascript; charset=utf-8" },
      })
    }

    if (url.pathname === "/styles.css") {
      return new Response(Bun.file(new URL("./styles.css", import.meta.url)), {
        headers: { "Content-Type": "text/css; charset=utf-8" },
      })
    }

    if (url.pathname === "/__ws") {
      const path = url.searchParams.get("path") || "/"
      const ok = server.upgrade(req, {
        data: {
          path,
          ui: normalizeUi(),
        },
      })
      if (ok) return
      return new Response("websocket upgrade failed\n", { status: 500 })
    }

    if (url.pathname === "/__stats") {
      return new Response(statsText({ state, connections }), {
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      })
    }

    const isKnown = url.pathname === "/" || /^\/task\/[^/]+$/.test(url.pathname)
    const status = isKnown ? 200 : 404

    return new Response(renderPage({
      state,
      path: url.pathname,
      ui: normalizeUi(),
    }), {
      status,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    })
  },

  websocket: {
    open(ws) {
      connections.add(ws)
      refresh(ws)
    },

    message(ws, raw) {
      let message
      try {
        message = JSON.parse(String(raw))
      } catch {
        ws.send(JSON.stringify({ error: "bad_json" }))
        return
      }

      const result = applyClientMessage(state, ws.data.ui, message)
      state = result.state
      ws.data.ui = result.ui

      if (result.broadcast) {
        broadcast()
      } else if (result.refresh) {
        refresh(ws)
      }
    },

    close(ws) {
      connections.delete(ws)
    },
  },
})

console.log(`bun taskboard listening on http://${HOST}:${server.port}`)
console.log(`open / and /task/1 to compare this baseline with examples/web_skeleton/server.lua`)
console.log(`stats at http://${HOST}:${server.port}/__stats`)
