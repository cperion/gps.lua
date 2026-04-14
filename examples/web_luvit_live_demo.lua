package.path = "./?.lua;./?/init.lua;" .. package.path

local http = require("http")
local net = require("net")
local timer = require("timer")
local pvm = require("pvm")
local web = require("web")
local json_parse = require("json.parse")
local json_decode = require("json.decode")

local T = pvm.context()
web.Define(T)

T:Define [[
    module App {
        Post = (string id, string slug, string title, string body) unique
        Site = (App.Post* posts, number next_id, string draft) unique
    }

    module Page {
        Nav = (string current_path, boolean logged_in, string? username) unique

        View = Home(Page.Nav nav, App.Post* posts, string draft) unique
             | Post(Page.Nav nav, App.Post post) unique
             | NotFound(Page.Nav nav, string path) unique
    }

    module DemoWeb {
        Header = (string name, string value) unique

        Body = PageBody(Page.View view) unique
             | HtmlBody(Html.Node node) unique

        Response = (number status, DemoWeb.Header* headers, DemoWeb.Body body) unique
    }

    module Event {
        Msg = AddPost | SetDraft(string value) unique | Click(string action, string? target_id) unique
    }
]]

local H = web.html(T)
local F = web.forms(T, H)
local R = web.render(T)
local Diff = web.diff(T)
local Encode = web.encode(T, R)
local Resp = web.response(T, "DemoWeb")

local HTTP_PORT = tonumber(os.getenv("PORT") or "8080")
local WS_PORT = tonumber(os.getenv("WS_PORT") or "8081")
local HOST = os.getenv("HOST") or "127.0.0.1"
local LivePage = web.live_page(H, WS_PORT)

local function nav_for(req)
    return T.Page.Nav(req.path, req.logged_in or false, req.username)
end

local function controls(draft)
    return H.kel("controls", "div", { H.cls("controls") }, {
        F.live_post("add-post", {}, {
            F.live_text_input("draft", "draft", "draft", {
                H.typ("text"),
                H.attr("value", draft),
                H.attr("placeholder", "Post title"),
            }),
            H.button({ H.typ("submit") }, { H.text("Add post") }),
        }, { key = "composer" }),
    })
end

local function page_shell(nav, title, content, draft)
    return LivePage.shell(title, {
        H.kel("nav", "nav", { H.cls("topnav") }, {
            H.a({ H.href("/") }, { H.text("Home") }),
            H.text(" · "),
            H.span({ H.cls("who") }, {
                H.text(nav.logged_in and (nav.username or "user") or "guest"),
            }),
        }),
        controls(draft),
        content,
    })
end

local function post_items(posts)
    local out = {}
    for i = 1, #posts do
        local post = posts[i]
        out[i] = H.kel("post:" .. post.id, "li", {}, {
            H.a({ H.href("/posts/" .. post.slug) }, { H.text(post.title) }),
        })
    end
    return out
end

local function post_list(posts)
    return H.kel("posts", "main", { H.cls("posts") }, {
        H.kel("posts-title", "h1", {}, { H.text("Posts") }),
        H.kel("posts-list", "ul", {}, post_items(posts)),
    })
end

local function post_page(post)
    return H.kel("post:" .. post.id, "main", { H.cls("post") }, {
        H.h1({}, { H.text(post.title) }),
        H.p({}, { H.text(post.body) }),
    })
end

local function not_found_page(path)
    return H.kel("not-found", "main", { H.cls("not-found") }, {
        H.h1({}, { H.text("404") }),
        H.p({}, { H.text("No route for " .. path) }),
    })
end

local template = pvm.phase("web.luvit.live.template", {
    [T.Page.Home] = function(self)
        return pvm.once(page_shell(self.nav, "Live Home", post_list(self.posts), self.draft))
    end,

    [T.Page.Post] = function(self)
        return pvm.once(page_shell(self.nav, self.post.title, post_page(self.post), ""))
    end,

    [T.Page.NotFound] = function(self)
        return pvm.once(page_shell(self.nav, "Not Found", not_found_page(self.path), ""))
    end,
})

local function find_post_by_slug(posts, slug)
    for i = 1, #posts do
        if posts[i].slug == slug then
            return posts[i]
        end
    end
    return nil
end

local site = T.App.Site({
    T.App.Post("1", "hello", "Hello", "First post"),
    T.App.Post("2", "pvm", "pvm", "Compiler-shaped web rendering"),
}, 3, "")

local function append_post(state, title, slug_prefix, body_prefix)
    local id = tostring(state.next_id)
    local post = T.App.Post(id, slug_prefix .. id, title, body_prefix .. " " .. id)
    local posts = {}
    for i = 1, #state.posts do
        posts[i] = state.posts[i]
    end
    posts[#posts + 1] = post
    return pvm.with(state, {
        posts = posts,
        next_id = state.next_id + 1,
        draft = "",
    })
end

local function apply(state, event)
    if event == T.Event.AddPost then
        local title = state.draft ~= "" and state.draft or ("live " .. tostring(state.next_id))
        return append_post(state, title, "live-", "Client pushed post")
    end
    if event.kind == "SetDraft" then
        return pvm.with(state, { draft = event.value })
    end
    return state
end

local function decode_event(text)
    local value = json_parse.parse(text)
    local kind = json_decode.field_string(value, "type")
    local action = json_decode.field_string(value, "action")

    if kind == "input" and action == "draft" then
        return T.Event.SetDraft(json_decode.field_string(value, "value"))
    end

    if kind == "submit" and action == "add-post" then
        return T.Event.AddPost
    end

    if kind == "click" then
        local target_v = json_decode.get(value, "target_id")
        local target_id = nil
        if target_v ~= nil and not json_decode.is_null(target_v) then
            target_id = json_decode.as_string(target_v)
        end
        return T.Event.Click(action, target_id)
    end

    error("unsupported client event kind: " .. tostring(kind) .. "/" .. tostring(action))
end

local routes = {
    {
        method = "GET",
        path = "/",
        build = function(req, state)
            return Resp.ok_page(T.Page.Home(nav_for(req), state.posts, state.draft))
        end,
    },
    {
        method = "GET",
        path = "/posts/:slug",
        build = function(req, state, params)
            local post = find_post_by_slug(state.posts, params.slug)
            if not post then
                return Resp.not_found_page(T.Page.NotFound(nav_for(req), req.path))
            end
            return Resp.ok_page(T.Page.Post(nav_for(req), post))
        end,
    },
    {
        method = "GET",
        path = "/__stats",
        build = function(_req, _state)
            return Resp.html(200, { ["Content-Type"] = "text/plain; charset=utf-8" }, H.raw(pvm.report_string({ template, R.render, R.render_live })))
        end,
    },
}

local resolve = web.router.compile(routes)

local function build_response(req)
    local route, params = resolve(req.method, req.path)
    if route then
        return route.build(req, site, params, nil)
    end
    return Resp.not_found_page(T.Page.NotFound(nav_for(req), req.path))
end

local function make_request(raw_req)
    local req = web.http.make_request(raw_req)
    req.logged_in = true
    req.username = "cedric"
    return req
end

local function build_html(req)
    return Resp.compile(template, build_response(req))
end

web.http.serve({
    http = http,
    host = HOST,
    port = HTTP_PORT,
    make_request = make_request,
    render = R.render_live,
    build = function(req)
        local response = build_response(req)
        return response.status, response.headers, Resp.compile(template, response)
    end,
})

local hub = web.live.hub({
    diff = Diff.diff,
    encode = Encode.batch,
    build_html = build_html,
    decode_message = function(text)
        return decode_event(text)
    end,
    on_message = function(event)
        site = apply(site, event)
    end,
    broadcast_after_message = true,
    on_error = function(err)
        io.stderr:write("live error: " .. tostring(err) .. "\n")
    end,
})

hub:serve_ws({
    net = net,
    host = HOST,
    port = WS_PORT,
    request = function(req)
        return {
            method = "GET",
            path = req.query.path or "/",
            logged_in = true,
            username = "cedric",
        }
    end,
    on_connect = function(_conn, req, live_hub)
        print("ws connected for", req.path, "connections=" .. tostring(live_hub:count()))
    end,
    on_close = function(_conn, live_hub)
        print("ws closed, connections=" .. tostring(live_hub:count()))
    end,
})

local function append_new_post()
    local id = tostring(site.next_id)
    site = append_post(site, "live " .. id, "live-", "Timer pushed post")
    print("live update -> appended post", id)
    hub:broadcast()
end

timer.setInterval(4000, append_new_post)

print("live web demo listening on http://" .. HOST .. ":" .. tostring(HTTP_PORT))
print("websocket endpoint on ws://" .. HOST .. ":" .. tostring(WS_PORT) .. "/?path=/")
print("open / in a browser and watch posts append every 4 seconds")
print("type in the keyed draft field and submit the keyed form to add a post")
print("stats at /__stats")
