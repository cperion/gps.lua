package.path = "./?.lua;./?/init.lua;" .. package.path

local http = require("http")
local net = require("net")
local pvm = require("pvm")
local web = require("web")
local json_parse = require("json.parse")
local json_decode = require("json.decode")

local T = pvm.context()
web.Define(T)
require("examples.web_skeleton.asdl").Define(T)

local H = web.html(T)
local F = web.forms(T, H)
local R = web.render(T)
local Diff = web.diff(T)
local Encode = web.encode(T, R)
local Resp = web.response(T, "AppWeb")

local reducers = require("examples.web_skeleton.apply").bind(T)
local Template = require("examples.web_skeleton.template")
local Routes = require("examples.web_skeleton.routes").bind(T, Resp)

local HOST = os.getenv("HOST") or "127.0.0.1"
local HTTP_PORT = tonumber(os.getenv("PORT") or "8080")
local WS_PORT = tonumber(os.getenv("WS_PORT") or "8081")

local STYLE_PATH = "/styles.css"
local CLIENT_PATH = "/client.js"
local BOOTSTRAP_PATH = "/bootstrap.js"

local assets = Template.assets(H, WS_PORT)
local template = Template.bind(T, H, F, WS_PORT, {
    stylesheet_href = STYLE_PATH,
    client_js_src = CLIENT_PATH,
    bootstrap_js_src = BOOTSTRAP_PATH,
})

local state = T.App.State({
    T.App.Task("1", "Ship taskboard demo", "Replace the toy list with a real live app and keep it fast.", T.App.High, false),
    T.App.Task("2", "Style the board", "Use a polished dark UI with cards, filters, and responsive layout.", T.App.Medium, false),
    T.App.Task("3", "Show live collaboration", "Open the board in two browser tabs and watch patches fan out.", T.App.Low, true),
}, 4)

local function nav_for(req)
    return T.Page.Nav(req.path, req.logged_in or false, req.username)
end

local function with_defaults(req)
    req = reducers.defaults(req)
    req.logged_in = true
    req.username = "cedric"
    return req
end

local routes = Routes.make(nav_for, function()
    return state
end, H, function()
    return pvm.report_string({ template, R.render, R.render_live })
end)

local resolve = web.router.compile(routes)

local function build_response(req)
    if req.path == STYLE_PATH then
        return Resp.html(200, { ["Content-Type"] = "text/css; charset=utf-8" }, H.raw(assets.css))
    end
    if req.path == CLIENT_PATH then
        return Resp.html(200, { ["Content-Type"] = "application/javascript; charset=utf-8" }, H.raw(assets.client_js))
    end
    if req.path == BOOTSTRAP_PATH then
        return Resp.html(200, { ["Content-Type"] = "application/javascript; charset=utf-8" }, H.raw(assets.bootstrap_js))
    end

    local route, params = resolve(req.method, req.path)
    if route then
        return route.build(req, state, params, nil)
    end
    return Resp.not_found_page(T.Page.NotFound(nav_for(req), req.path, Routes.summary_of(state.tasks)))
end

local function build_html(req)
    return Resp.compile(template, build_response(req))
end

local function make_request(raw_req)
    local req = web.http.make_request(raw_req)
    return with_defaults(req)
end

local function target_id_for(action, value)
    local target_v = json_decode.get(value, "target_id")
    if target_v == nil or json_decode.is_null(target_v) then
        error("missing target_id for action " .. tostring(action))
    end
    return json_decode.as_string(target_v)
end

local function decode_message(text, req)
    local value = json_parse.parse(text)
    local kind = json_decode.field_string(value, "type")
    local action = json_decode.field_string(value, "action")

    if kind == "input" then
        local input_value = json_decode.field_string(value, "value")

        if action == "draft-title" then
            return T.Event.SetDraftTitle(input_value)
        end
        if action == "draft-notes" then
            return T.Event.SetDraftNotes(input_value)
        end
        if action == "search" then
            return T.Event.SetSearch(input_value)
        end
        if action == "task-title" then
            return T.Event.SetTaskTitle(target_id_for(action, value), input_value)
        end
        if action == "task-notes" then
            return T.Event.SetTaskNotes(target_id_for(action, value), input_value)
        end
    end

    if kind == "submit" and action == "add-task" then
        return T.Event.AddTask(req.draft_title, req.draft_notes, req.draft_priority)
    end

    if kind == "click" then
        if action == "cycle-draft-priority" then
            return T.Event.CycleDraftPriority
        end
        if action == "filter-all" then
            return T.Event.SetFilter(T.App.All)
        end
        if action == "filter-open" then
            return T.Event.SetFilter(T.App.Open)
        end
        if action == "filter-done" then
            return T.Event.SetFilter(T.App.Done)
        end
        if action == "clear-completed" then
            return T.Event.ClearCompleted
        end
        if action == "toggle-task" then
            return T.Event.ToggleTask(target_id_for(action, value))
        end
        if action == "delete-task" then
            return T.Event.DeleteTask(target_id_for(action, value))
        end
        if action == "cycle-task-priority" then
            return T.Event.CycleTaskPriority(target_id_for(action, value))
        end
    end

    error("unsupported event: " .. tostring(kind) .. "/" .. tostring(action))
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
    build_html = build_html,
    diff = Diff.diff,
    encode = Encode.batch,
    normalize_request = with_defaults,
    decode_message = decode_message,
    on_message = function(event, conn, req, live_hub, record)
        if reducers.is_request_event(event) then
            record.req = reducers.request(req, event)
            live_hub:refresh(conn)
            return
        end

        local next_state = reducers.state(state, event)
        local state_changed = next_state ~= state
        state = next_state

        if event.kind == "AddTask" then
            record.req = reducers.clear_composer(req)
            live_hub:broadcast()
            return
        end

        if state_changed then
            live_hub:broadcast()
        end
    end,
    on_error = function(err)
        io.stderr:write("taskboard live error: " .. tostring(err) .. "\n")
    end,
})

hub:serve_ws({
    net = net,
    host = HOST,
    port = WS_PORT,
    request = function(req)
        return with_defaults({
            method = "GET",
            path = req.query.path or "/",
        })
    end,
    on_connect = function(_conn, req, live_hub)
        print("ws connected for", req.path, "connections=" .. tostring(live_hub:count()))
    end,
    on_close = function(_conn, live_hub)
        print("ws closed, connections=" .. tostring(live_hub:count()))
    end,
})

print("taskboard listening on http://" .. HOST .. ":" .. tostring(HTTP_PORT))
print("websocket endpoint on ws://" .. HOST .. ":" .. tostring(WS_PORT) .. "/?path=/")
print("open / in two tabs to watch local filters stay local while task updates broadcast")
print("stats at /__stats")
