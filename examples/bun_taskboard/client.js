(function (global) {
  function socketUrl() {
    var proto = location.protocol === "https:" ? "wss://" : "ws://"
    return proto + location.host + "/__ws?path=" + encodeURIComponent(location.pathname)
  }

  function send(ws, message) {
    if (!ws || ws.readyState !== 1) return false
    ws.send(JSON.stringify(message))
    return true
  }

  function connect(opts) {
    opts = opts || {}
    var ws = new WebSocket(opts.url || socketUrl())

    ws.onmessage = function (event) {
      var message = JSON.parse(event.data)
      if (message.title) document.title = message.title
      if (message.html) {
        var root = document.getElementById("app-root")
        if (root) root.outerHTML = message.html
      }
    }

    document.addEventListener("click", function (event) {
      var target = event.target && event.target.closest ? event.target.closest("[data-action]") : null
      if (!target) return
      if (target.tagName === "A") return
      if (target.form && target.tagName === "BUTTON" && target.type === "submit") return

      event.preventDefault()
      send(ws, {
        type: "click",
        action: target.getAttribute("data-action"),
        target_id: target.getAttribute("data-target-id")
      })
    })

    document.addEventListener("submit", function (event) {
      var form = event.target && event.target.closest ? event.target.closest("form[data-action]") : null
      if (!form) return
      event.preventDefault()
      send(ws, {
        type: "submit",
        action: form.getAttribute("data-action")
      })
    })

    document.addEventListener("input", function (event) {
      var input = event.target
      if (!input || !input.getAttribute) return
      if (input.getAttribute("data-live") !== "input") return
      var action = input.getAttribute("data-action")
      if (!action) return
      send(ws, {
        type: "input",
        action: action,
        target_id: input.getAttribute("data-target-id"),
        value: input.value == null ? "" : String(input.value)
      })
    })

    ws.sendMessage = function (message) {
      return send(ws, message)
    }

    return ws
  }

  global.BunTaskboard = {
    connect: connect
  }
})(typeof window !== "undefined" ? window : this)
