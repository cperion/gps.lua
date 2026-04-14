package.path = "./?.lua;./?/init.lua;" .. package.path

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
local Diff = web.diff(T)
local Encode = web.encode(T, R)

local Header = T.DemoWeb.Header
local Response = T.DemoWeb.Response
local PageBody = T.DemoWeb.PageBody
local HtmlBody = T.DemoWeb.HtmlBody

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

local template = pvm.phase("web.demo.template", {
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

local routes = {
    {
        method = "GET",
        path = "/",
        build = function(req, site)
            return Response(
                200,
                { Header("Content-Type", "text/html; charset=utf-8") },
                PageBody(T.Page.Home(nav_for(req), site.posts))
            )
        end,
    },
    {
        method = "GET",
        path = "/posts/:slug",
        build = function(req, site, params)
            local post = find_post_by_slug(site.posts, params.slug)
            if not post then
                return Response(
                    404,
                    { Header("Content-Type", "text/html; charset=utf-8") },
                    PageBody(T.Page.NotFound(nav_for(req), req.path))
                )
            end
            return Response(
                200,
                { Header("Content-Type", "text/html; charset=utf-8") },
                PageBody(T.Page.Post(nav_for(req), post))
            )
        end,
    },
    {
        method = "GET",
        path = "/fragment/posts",
        build = function(req, site)
            return Response(
                200,
                { Header("Content-Type", "text/html; charset=utf-8") },
                HtmlBody(post_list(site.posts))
            )
        end,
    },
}

local resolve = web.router.compile(routes)

local function body_to_html(body)
    if body.kind == "PageBody" then
        return pvm.one(template(body.view))
    end
    return body.node
end

local function render_response(response, live)
    local html = body_to_html(response.body)
    if live then
        return R.to_string_live(html), html
    end
    return R.to_string(html), html
end

local function request(site, method, path, opts)
    local route, params = resolve(method, path)
    local req = {
        method = method,
        path = path,
        logged_in = opts and opts.logged_in or false,
        username = opts and opts.username or nil,
    }

    local response
    if route then
        response = route.build(req, site, params, nil)
    else
        response = Response(
            404,
            { Header("Content-Type", "text/html; charset=utf-8") },
            PageBody(T.Page.NotFound(nav_for(req), path))
        )
    end

    local html_string, html_tree = render_response(response, false)
    print("==", method, path)
    print("status", response.status)
    print(html_string)
    print()
    return response, html_tree
end

local site = T.App.Site({
    T.App.Post("1", "hello", "Hello", "First post"),
    T.App.Post("2", "pvm", "pvm", "Compiler-shaped web rendering"),
})

local _, home_html_v1 = request(site, "GET", "/", { logged_in = true, username = "cedric" })
request(site, "GET", "/posts/hello", { logged_in = true, username = "cedric" })
request(site, "GET", "/fragment/posts")
request(site, "GET", "/missing")

local site2 = pvm.with(site, {
    posts = {
        site.posts[1],
        site.posts[2],
        T.App.Post("3", "web", "web", "Structural SSR")
    }
})

local response2 = routes[1].build({ method = "GET", path = "/", logged_in = true, username = "cedric" }, site2, {}, nil)
local _, home_html_v2 = render_response(response2, true)

print("== live patch from home v1 -> v2")
local batch = Diff.diff(home_html_v1, home_html_v2)
print(Encode.batch(batch))
print()

print("== cache report")
print(pvm.report_string({ template, R.render, R.render_live }))
