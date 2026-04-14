local ui = require("ui.init")
local app = require("ui.demo.app")
local LoveBackend = require("ui.demo.love_backend")

local FOOTER_H = 24

local demo = {
    session = nil,
    state = nil,
    backend = nil,
    tree = nil,
    sem = nil,
    view = nil,
    runtime = nil,
    layout = nil,
    tree_rev = nil,
    view_rev = nil,
    tree_focus = nil,
    gc_step_kb = 220,
    mem_kb = 0,
    mem_peak_kb = 0,
    stats = {
        rebuilds = 0,
        runtime_builds = 0,
    },
    input = {
        pressed = false,
        released = false,
        scroll_x = 0,
        scroll_y = 0,
        focus_next = false,
        focus_prev = false,
        activate = false,
        press_x = 0,
        press_y = 0,
    },
}

local function current_frame()
    return ui.frame(0, 0, love.graphics.getWidth(), math.max(0, love.graphics.getHeight() - FOOTER_H))
end

local function replace_state(next_state)
    demo.state = next_state
    return next_state
end

local function replace_view(next_view)
    demo.view = next_view
    return next_view
end

local function sync_layout()
    local w, h = love.graphics.getDimensions()
    h = math.max(0, h - FOOTER_H)
    local changed = (not demo.layout) or demo.layout.width ~= w or demo.layout.height ~= h
    if changed then
        demo.layout = app.compute_layout(w, h)
        demo.view_rev = nil
        demo.tree_rev = nil
        demo.tree_focus = nil
    end
    return demo.layout, changed
end

local function sync_tree(force)
    local layout = sync_layout()
    local focused_id = (demo.session and demo.session.state.focused) or ""
    local rev = demo.state and demo.state.rev or 0

    if force or (not demo.view) or demo.view_rev ~= rev then
        replace_view(app.build_view(demo.state, layout, {
            focused_id = focused_id,
        }))
        demo.view_rev = rev
    end

    if force
        or (not demo.tree)
        or demo.tree_rev ~= rev
        or demo.tree_focus ~= focused_id then
        demo.tree, demo.sem = app.build_tree(demo.state, layout, {
            focused_id = focused_id,
            view = demo.view,
        })
        demo.tree_rev = rev
        demo.tree_focus = focused_id
        demo.stats.rebuilds = demo.stats.rebuilds + 1
    end
end

local function sync_runtime()
    demo.runtime = app.build_runtime(demo.state, sync_layout(), {
        focused_id = (demo.session and demo.session.state.focused) or "",
        view = demo.view,
        runtime = demo.runtime,
    })
    demo.stats.runtime_builds = demo.stats.runtime_builds + 1
end

local function reset_input_edges()
    demo.input.pressed = false
    demo.input.released = false
    demo.input.scroll_x = 0
    demo.input.scroll_y = 0
    demo.input.focus_next = false
    demo.input.focus_prev = false
    demo.input.activate = false
end

local function update_memory_stats()
    demo.mem_kb = collectgarbage("count")
    if demo.mem_kb > demo.mem_peak_kb then
        demo.mem_peak_kb = demo.mem_kb
    end
end

function love.load()
    math.randomseed(os.time())
    collectgarbage("setpause", 110)
    collectgarbage("setstepmul", 300)

    love.graphics.setBackgroundColor(0.02, 0.04, 0.07, 1)

    demo.backend = LoveBackend.new({ sizes = app.font_sizes() })
    demo.session = ui.new_session({ backend = demo.backend })
    replace_state(app.new_state())
    demo.session:focus("action:play")

    sync_layout()
    sync_runtime()
    sync_tree(true)
    update_memory_stats()
end

function love.resize()
    sync_layout()
    sync_runtime()
    sync_tree(true)
end

function love.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        love.event.quit()
        return
    end

    local handled
    local next_state
    next_state, handled = app.keypressed(demo.state, key, {
        session = demo.session,
        layout = demo.layout or sync_layout(),
        isrepeat = isrepeat,
        mods = {
            shift = love.keyboard.isDown("lshift", "rshift"),
            ctrl = love.keyboard.isDown("lctrl", "rctrl"),
            alt = love.keyboard.isDown("lalt", "ralt"),
        },
    })
    replace_state(next_state)

    if not handled and not isrepeat then
        if key == "tab" then
            if love.keyboard.isDown("lshift", "rshift") then
                demo.input.focus_prev = true
            else
                demo.input.focus_next = true
            end
        elseif key == "return" or key == "kpenter" or key == "space" then
            demo.input.activate = true
        end
    end

    sync_tree(false)
end

function love.textinput(text)
    local handled
    local next_state
    next_state, handled = app.textinput(demo.state, text, {
        session = demo.session,
        layout = demo.layout or sync_layout(),
    })
    replace_state(next_state)
    if handled then
        sync_tree(false)
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        demo.input.pressed = true
        demo.input.press_x = x
        demo.input.press_y = y
    end
end

function love.mousereleased(_, _, button)
    if button == 1 then
        demo.input.released = true
    end
end

function love.wheelmoved(x, y)
    demo.input.scroll_x = demo.input.scroll_x + x
    demo.input.scroll_y = demo.input.scroll_y + y
end

function love.update(dt)
    replace_state(app.update(demo.state, dt))
    sync_runtime()
    sync_tree(false)

    local mx, my = love.mouse.getPosition()
    local down = love.mouse.isDown(1)
    local dragging = down and (math.abs(mx - demo.input.press_x) + math.abs(my - demo.input.press_y) > 4)

    demo.session:frame(demo.tree, {
        frame = current_frame(),
        input = {
            x = mx,
            y = my,
            down = down,
            pressed = demo.input.pressed,
            released = demo.input.released,
            dragging = dragging,
            scroll_x = demo.input.scroll_x,
            scroll_y = demo.input.scroll_y,
            focus_next = demo.input.focus_next,
            focus_prev = demo.input.focus_prev,
            activate = demo.input.activate,
        },
        runtime = demo.runtime,
        font_height = app.font_height,
        text_measure = function(style, text, max_w, max_h, node, opts)
            return demo.backend:measure_text(style, text, max_w, max_h, node, opts)
        end,
        draw = false,
    })

    local next_state = app.handle_messages(demo.state, demo.session:messages(), demo.layout)
    if next_state ~= demo.state then
        replace_state(next_state)
        sync_runtime()
        sync_tree(false)
    end

    collectgarbage("step", demo.gc_step_kb)
    update_memory_stats()
    reset_input_edges()
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    local footer_y = h - FOOTER_H + 4

    love.graphics.clear(0.02, 0.04, 0.07, 1)
    demo.session:draw(demo.tree, {
        frame = current_frame(),
        runtime = demo.runtime,
        view = demo.view,
        resolve_runtime_text = app.resolve_runtime_text,
        draw_custom_paint = app.draw_custom_paint,
        font_height = app.font_height,
        text_measure = function(style, text, max_w, max_h, node, opts)
            return demo.backend:measure_text(style, text, max_w, max_h, node, opts)
        end,
    })

    love.graphics.setScissor()
    love.graphics.origin()
    love.graphics.setFont(demo.backend:get_font(4))
    love.graphics.setColor(0.55, 0.67, 0.82, 1)
    local left, right = "", ""
    if demo.state and app.footer then
        left, right = app.footer(demo.state)
    end
    love.graphics.setColor(0.09, 0.12, 0.18, 0.98)
    love.graphics.rectangle("fill", 0, h - FOOTER_H, w, FOOTER_H)
    love.graphics.setColor(0.18, 0.22, 0.32, 1)
    love.graphics.line(0, h - FOOTER_H, w, h - FOOTER_H)
    love.graphics.setColor(0.55, 0.67, 0.82, 1)
    love.graphics.print(
        string.format("fps %d   mem %.1f MB (peak %.1f)   focused %s   tree builds %d",
            love.timer.getFPS(),
            demo.mem_kb / 1024,
            demo.mem_peak_kb / 1024,
            tostring(demo.session.state.focused or "-"),
            demo.stats.rebuilds),
        10,
        footer_y)
    love.graphics.printf(left or "", 280, footer_y, math.max(0, w - 700), "left")
    love.graphics.printf(right or "", math.max(0, w - 420), footer_y, 410, "right")
end
