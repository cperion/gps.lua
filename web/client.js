(function (global) {
  function byKey(root, key) {
    if (!root) return null
    if (root.nodeType === 1 && root.getAttribute("data-pvm-key") === key) {
      return root
    }
    return root.querySelector('[data-pvm-key="' + CSS.escape(key) + '"]')
  }

  function resolvePath(path) {
    if (!path || path.length === 0) {
      return document.documentElement
    }
    var node = document.documentElement
    for (var i = 0; i < path.length; i++) {
      node = byKey(node, path[i])
      if (!node) return null
    }
    return node
  }

  function applyPatch(patch) {
    var node = resolvePath(patch.path)

    if (patch.op === "replace") {
      if (!node) return
      if (!patch.path || patch.path.length === 0) {
        document.documentElement.outerHTML = patch.html
        return
      }
      node.outerHTML = patch.html
      return
    }

    if (patch.op === "remove") {
      if (node) node.remove()
      return
    }

    if (patch.op === "append") {
      if (node) node.insertAdjacentHTML("beforeend", patch.html)
      return
    }

    if (patch.op === "set_attr") {
      if (!node) return
      if (patch.name === "value" && "value" in node) {
        node.value = patch.value === undefined ? "" : patch.value
      }
      if (patch.value === undefined) {
        node.setAttribute(patch.name, "")
      } else {
        node.setAttribute(patch.name, patch.value)
      }
      return
    }

    if (patch.op === "remove_attr") {
      if (!node) return
      node.removeAttribute(patch.name)
      if (patch.name === "value" && "value" in node) {
        node.value = ""
      }
      return
    }

    if (patch.op === "set_text") {
      if (node) node.textContent = patch.text
      return
    }
  }

  function connect(opts) {
    opts = opts || {}
    var url = opts.url || (
      location.origin.replace(/^http/, "ws") + (opts.path || "/__web")
    )
    var ws = new WebSocket(url)

    function send(message) {
      if (ws.readyState !== 1) return false
      ws.send(JSON.stringify(message))
      return true
    }

    ws.onmessage = function (e) {
      var patches = JSON.parse(e.data)
      for (var i = 0; i < patches.length; i++) {
        applyPatch(patches[i])
      }
    }

    if (opts.captureClicks !== false) {
      document.addEventListener("click", function (e) {
        var target = e.target && e.target.closest ? e.target.closest("[data-pvm-action]") : null
        if (!target || target.getAttribute("data-pvm-event") === "input") return

        var form = e.target && e.target.closest ? e.target.closest("form[data-pvm-action]") : null
        if (form && target === form) {
          return
        }

        e.preventDefault()
        send({
          type: "click",
          action: target.getAttribute("data-pvm-action"),
          target_id: target.getAttribute("data-target-id")
        })
      })
    }

    if (opts.captureSubmit !== false) {
      document.addEventListener("submit", function (e) {
        var el = e.target && e.target.closest && e.target.closest("form[data-pvm-action]")
        if (!el) return
        e.preventDefault()
        send({
          type: "submit",
          action: el.getAttribute("data-pvm-action"),
          target_id: el.getAttribute("data-target-id")
        })
      })
    }

    if (opts.captureInput !== false) {
      document.addEventListener("input", function (e) {
        var el = e.target
        if (!el || !el.getAttribute) return
        if (el.getAttribute("data-pvm-event") !== "input") return
        var action = el.getAttribute("data-pvm-action")
        if (!action) return
        send({
          type: "input",
          action: action,
          target_id: el.getAttribute("data-target-id"),
          value: el.value == null ? "" : String(el.value)
        })
      })
    }

    ws.sendMessage = send
    return ws
  }

  global.PVMWeb = {
    connect: connect,
    applyPatch: applyPatch,
    resolvePath: resolvePath
  }
})(typeof window !== "undefined" ? window : this)
