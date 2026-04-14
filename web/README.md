# web

Structural SSR + live HTML patching for pvm.

`web/` is a small library layer, not a full app architecture.
It owns the generic web vocabulary:

- `Html.*` — structural HTML tree
- `Patch.*` — coarse live patch operations
- renderers, router, HTTP adapter, WebSocket transport, live hub

Your app should still own:

- `App.*` — domain state
- `Page.*` — render-facing view nouns
- `Web.*` / response types if you want typed responses
- `Event.*` — client/server events

The intended shape is:

```text
App.State
  ↓ route/build
Page.View
  ↓ template phase
Html.Node
  ↓ render phase
string fragments
  ↓ stream
HTTP response
```

and for live mode:

```text
client event JSON
  ↓ decode to app Event ASDL
apply(state, event) -> state
  ↓ rebuild page/html
old Html vs new Html
  ↓ Patch.Batch
JSON patches over websocket
```

## Modules

- `web/asdl.lua` — defines `Html.*` and `Patch.*`
- `web/html.lua` — HTML constructor helpers
- `web/render.lua` — `Html.Node -> string fragments`
- `web/router.lua` — simple method/path router
- `web/stream.lua` — triplet pump
- `web/http.lua` — luvit HTTP adapter
- `web/ws.lua` — minimal raw WebSocket server/connection helpers
- `web/live.lua` — live connection hub built on `web.ws`
- `web/live_page.lua` — shared live-page shell/bootstrap helpers
- `web/response.lua` — typed response helpers over app-owned `Web` modules
- `web/forms.lua` — form + csrf helper constructors
- `web/diff.lua` — keyed diff producing `Patch.Batch`
- `web/encode.lua` — patch JSON encoder
- `web/client.js` — tiny browser patch applicator + event sender
- `web/init.lua` — public facade

## Public facade

```lua
local web = require("web")
local T = pvm.context()
web.Define(T)

local H = web.html(T)
local R = web.render(T)
local Diff = web.diff(T)
local Encode = web.encode(T, R)
```

## Framework-owned ASDL

```lua
web.Define(T)
```

Defines:

### `Html`

```asdl
module Html {
    Node = Doc(string doctype, Html.Node root) unique
         | El(string tag, string? key, Html.Attr* attrs, Html.Node* children) unique
         | Text(string content) unique
         | Raw(string html) unique
         | Fragment(Html.Node* children) unique
         | Empty unique

    Attr = Str(string name, string value) unique
         | Bool(string name) unique
}
```

### `Patch`

```asdl
module Patch {
    Seg = Key(string key) unique
    Path = (Patch.Seg* segs) unique

    Op = Replace(Patch.Path path, Html.Node node) unique
       | Remove(Patch.Path path) unique
       | Append(Patch.Path path, Html.Node node) unique

    Batch = (Patch.Op* ops) unique
}
```

## HTML helpers

Bind helpers to your context:

```lua
local H = web.html(T)
```

Core helpers:

- `H.doc(root)`
- `H.doc_type(doctype, root)`
- `H.el(tag, attrs, children)`
- `H.kel(key, tag, attrs, children)`
- `H.text(x)`
- `H.raw(html)`
- `H.frag(children)`
- `H.empty`

Common attrs:

- `H.attr(name, value)`
- `H.bool(name, on)`
- `H.cls(name)`
- `H.id(name)`
- `H.href(url)`
- `H.src(url)`
- `H.typ(value)`
- `H.data(name, value)`

Live/event attrs:

- `H.pvm_action(action)` → `data-pvm-action="..."`
- `H.pvm_target(id)` → `data-target-id="..."`
- `H.pvm_event(kind)` → `data-pvm-event="..."`

Composition helpers:

- `H.when(cond, node)`
- `H.maybe(value, fn)`
- `H.each(items, fn)`

`web.html` normalizes attrs:

- drops `nil`
- sorts attrs canonically
- rejects duplicate attribute names

## Renderers

```lua
local R = web.render(T)
```

Returns:

- `R.render` — normal SSR renderer
- `R.render_live` — emits `data-pvm-key` for keyed nodes
- `R.to_string(node)`
- `R.to_string_live(node)`

The handlers are ordinary pvm phases returning string fragment streams.

## Router

```lua
local resolve = web.router.compile({
    {
        method = "GET",
        path = "/posts/:slug",
        build = function(req, state, params)
            ...
        end,
    },
})
```

Supported in v1:

- literal segments
- `:param` segments

## HTTP adapter

`web.http` is a small luvit-facing wrapper around the render triplet.

```lua
local http = require("http")

web.http.serve({
    http = http,
    host = "127.0.0.1",
    port = 8080,

    make_request = function(raw_req)
        local req = web.http.make_request(raw_req)
        req.logged_in = true
        req.username = "cedric"
        return req
    end,

    render = R.render,

    build = function(req)
        local response = build_response(req)
        return response.status, response.headers, body_to_html(response.body)
    end,
})
```

`build(req)` must return:

```lua
status, headers, html_node
```

where `headers` is either:

- an array of typed header nodes you convert later, or
- a plain `{ [name] = value }` table

## WebSocket transport

`web.ws` is a minimal raw WebSocket layer intended for the live hub.

```lua
local net = require("net")

web.ws.serve({
    net = net,
    host = "127.0.0.1",
    port = 8081,
    on_connect = function(conn, req)
        conn:on_text(function(text)
            print(text)
        end)
    end,
})
```

Current support:

- HTTP upgrade handshake
- masked client text frames
- server text frames
- ping/pong
- close

Not yet supported:

- fragmentation
- binary frames
- huge 64-bit payload lengths

## Live hub

`web.live.hub(...)` manages per-connection `last_sent` Html trees.

```lua
local hub = web.live.hub({
    build_html = build_html,   -- req -> Html.Node
    diff = Diff.diff,          -- (old, new) -> Patch.Batch
    encode = Encode.batch,     -- Patch.Batch -> JSON string

    decode_message = function(text, req)
        return decode_event(text)
    end,

    on_message = function(event, conn, req, hub)
        app_state = apply(app_state, event)
    end,

    broadcast_after_message = true,
})
```

Then serve websocket connections through the hub:

```lua
hub:serve_ws({
    net = require("net"),
    host = "127.0.0.1",
    port = 8081,

    request = function(req)
        return {
            method = "GET",
            path = req.query.path or "/",
            logged_in = true,
            username = "cedric",
        }
    end,
})
```

Useful methods:

- `hub:count()`
- `hub:record(conn)`
- `hub:set_request(conn, req)`
- `hub:refresh(conn)`
- `hub:broadcast()`
- `hub:dispatch(conn, text)`

## Client runtime

`web/client.js` does three things:

1. opens a websocket
2. applies incoming patch JSON to DOM nodes addressed by `data-pvm-key`
3. sends declarative events back to the server

By default it captures:

- click on `[data-pvm-action]`
- submit on `form[data-pvm-action]`
- input on `[data-pvm-action][data-pvm-event="input"]`

Outgoing messages are JSON like:

```json
{"type":"click","action":"add-post","target_id":null}
```

or

```json
{"type":"input","action":"search","target_id":"query","value":"abc"}
```

The framework does **not** impose an event ASDL. Your app decodes this JSON into its own `Event.*` values.

## Live page shell helper

If multiple pages need the same browser runtime + websocket bootstrap, bind:

```lua
local LivePage = web.live_page(H, ws_port)
```

Helpers:

- `LivePage.bootstrap_script(path_expr?)`
- `LivePage.script_nodes(path_expr?)`
- `LivePage.shell(title, body_children, opts?)`

Typical usage:

```lua
local function shell(title, body_children)
    return LivePage.shell(title, body_children)
end
```

This removes the duplicated `client.js` embedding and websocket bootstrap script from app templates.

## Typed response helpers

If your app defines a response module like:

```asdl
module AppWeb {
    Header = (string name, string value) unique
    Body = PageBody(Page.View view) unique
         | HtmlBody(Html.Node node) unique
    Response = (number status, AppWeb.Header* headers, AppWeb.Body body) unique
}
```

bind helpers with:

```lua
local Resp = web.response(T, "AppWeb")
```

Useful functions:

- `Resp.header(name, value)`
- `Resp.headers({ [name] = value })`
- `Resp.page(status, headers, view)`
- `Resp.html(status, headers, node)`
- `Resp.ok_page(view, headers)`
- `Resp.ok_html(node, headers)`
- `Resp.not_found_page(view, headers)`
- `Resp.compile(template, response)`

`Resp.compile(template, response)` turns your typed body into `Html.Node` by applying the template phase for `PageBody` and passing `HtmlBody` through unchanged.

## Forms and csrf helpers

Bind form helpers with:

```lua
local F = web.forms(T, H)
```

Helpers:

- `F.csrf_hidden(token)`
- `F.hidden(name, value)`
- `F.post(attrs, children, { csrf_token = ..., key = ... })`
- `F.live_post(action, attrs, children, { csrf_token = ..., key = ... })`
- `F.text_input(action, target_id, attrs, { key = ... })`
- `F.live_text_input(key, action, target_id, attrs)`

The csrf story is intentionally simple: the framework does not own sessions or tokens. Your app generates the token, and `F.csrf_hidden(token)` / `F.post(..., { csrf_token = token })` place it in the form as a hidden input.

## Keys and live diff

Live diff is keyed.

If a subtree should be independently patchable, give it a stable key:

```lua
H.kel("posts", "main", ..., ...)
H.kel("post:" .. post.id, "li", ..., ...)
```

This is especially important for interactive controls. If a form or input is allowed to sit inside an unkeyed region, a small state change may force replacement of a larger ancestor and you will lose focus/caret position. In practice:

- use keyed helpers like `F.live_text_input(...)` for live-controlled fields

- key the form region
- key the input itself if its value is live-updated
- prefer small attr/text patches over subtree replacement

Current diff behavior is intentionally coarse but now includes small in-place edits:

- identical interned subtree → skip
- keyed append/remove → emit patch
- attribute changes on keyed elements → `set_attr` / `remove_attr`
- single-text-child changes on keyed elements → `set_text`
- otherwise replace the nearest keyed region

This keeps the client runtime tiny while avoiding unnecessary full-subtree replacement for small updates.

## Safety rules

- `Text` always escapes
- `Raw` is trusted HTML only
- template functions should stay pure
- no hidden request/session ctx inside templates
- if rendering depends on a value, put it in your `Page.*` ASDL

## Examples

- `examples/web_demo.lua` — offline SSR + diff demo
- `examples/web_luvit_demo.lua` — HTTP SSR server
- `examples/web_luvit_live_demo.lua` — HTTP + WebSocket live updates
- `examples/web_skeleton/server.lua` — canonical small app skeleton using responses, forms, http, ws, and live hub

## Recommended app split

```text
App.*     -- domain/source truth
Page.*    -- render-facing view nouns
Event.*   -- client/server events
Html.*    -- framework-owned structural HTML
Patch.*   -- framework-owned live patch ops
```

That keeps the framework generic and the app architecture in your ASDL where pvm can see it.
