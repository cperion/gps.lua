package.path = "./?.lua;./?/init.lua;" .. package.path

local http = require("http")
local pvm = require("pvm")
local web = require("web")

local T = pvm.context()
web.Define(T)

T:Define [[
    module App {
        Post = (string id, string slug, string title, string body) unique
        Site = (App.Post* posts) unique
    }

    module Page {
        Nav = (string current_path, boolean logged_in, string? username) unique

        View = Home(Page.Nav nav, App.Post* posts) unique
             | Post(Page.Nav nav, App.Post post) unique
             | NotFound(Page.Nav nav, string path) unique
    }

    module DemoWeb {
        Header = (string name, string value) unique

        Body = PageBody(Page.View view) unique
             | HtmlBody(Html.Node node) unique

        Response = (number status, DemoWeb.Header* headers, DemoWeb.Body body) unique
    }
]]

local H = web.html(T)
local R = web.render(T)
local Resp = web.response(T, "DemoWeb")

local function nav_for(req)
    return T.Page.Nav(req.path, req.logged_in or false, req.username)
end

local function page_shell(nav, title, content)
    return H.doc(H.kel("root", "html", {}, {
        H.head({}, {
            H.title({}, { H.text(title) }),
            H.meta({ H.attr("charset", "utf-8") }),
        }),
        H.kel("page", "body", {}, {
            H.kel("nav", "nav", { H.cls("topnav") }, {
                H.a({ H.href("/") }, { H.text("Home") }),
                H.text(" · "),
                H.span({ H.cls("who") }, {
                    H.text(nav.logged_in and (nav.username or "user") or "guest"),
                }),
            }),
            content,
        }),
    }))
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

local template = pvm.phase("web.luvit.demo.template", {
    [T.Page.Home] = function(self)
        return pvm.once(page_shell(self.nav, "Home", post_list(self.posts)))
    end,

    [T.Page.Post] = function(self)
        return pvm.once(page_shell(self.nav, self.post.title, post_page(self.post)))
    end,

    [T.Page.NotFound] = function(self)
        return pvm.once(page_shell(self.nav, "Not Found", not_found_page(self.path)))
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
    T.App.Post("3", "web", "web", "Streaming structural SSR on LuaJIT"),
})

local routes = {
    {
        method = "GET",
        path = "/",
        build = function(req, state)
            return Resp.ok_page(T.Page.Home(nav_for(req), state.posts))
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
        path = "/fragment/posts",
        build = function(_req, state)
            return Resp.ok_html(post_list(state.posts))
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

local port = tonumber(os.getenv("PORT") or "8080")
local host = os.getenv("HOST") or "127.0.0.1"

web.http.serve({
    http = http,
    host = host,
    port = port,
    make_request = make_request,
    render = R.render,
    build = function(req)
        local response = build_response(req)
        return response.status, response.headers, Resp.compile(template, response)
    end,
})

print("web demo listening on http://" .. host .. ":" .. tostring(port))
print("  /")
print("  /posts/hello")
print("  /fragment/posts")
print("  /__stats")
