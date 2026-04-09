local ui = require("ui.init")
local app = require("ui.demo.app")
local LoveBackend = require("ui.demo.love_backend")

local demo = {
    session = nil,
    state = nil,
    backend = nil,
    tree = nil,
    sem = nil,
    runtime = nil,
    layout = nil,
    tree_rev = nil,
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
        press_x = 0,
        press_y = 0,
    },
}

local function current_frame()
    return ui.frame(0, 0, love.graphics.getWidth(), love.graphics.getHeight())
end

local function sync_layout()
    local w, h = love.graphics.getDimensions()
    if (not demo.layout) or demo.layout.width ~= w or demo.layout.height ~= h then
        demo.layout = app.compute_layout(w, h)
        if demo.session then
            demo.session:clear_measure_cache()
        end
    end
    return demo.layout
end

local function sync_tree(force)
    local layout = sync_layout()
    local focused_id = (demo.session and demo.session.state.focused) or ""
    local rev = demo.state and demo.state.rev or 0

    if force
        or (not demo.tree)
        or demo.tree_rev ~= rev
        or demo.tree_focus ~= focused_id then
        demo.tree, demo.sem = app.build_tree(demo.state, layout, {
            focused_id = focused_id,
        })
        demo.tree_rev = rev
        demo.tree_focus = focused_id
        demo.stats.rebuilds = demo.stats.rebuilds + 1
    end
end

local function sync_runtime()
    demo.runtime = app.build_runtime(demo.state, sync_layout())
    demo.stats.runtime_builds = demo.stats.runtime_builds + 1
end

local function reset_input_edges()
    demo.input.pressed = false
    demo.input.released = false
    demo.input.scroll_x = 0
    demo.input.scroll_y = 0
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
    demo.state = app.new_state()

    sync_layout()
    sync_tree(true)
    sync_runtime()
    update_memory_stats()
end

function love.resize()
    sync_layout()
    sync_tree(true)
    sync_runtime()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end
    app.keypressed(demo.state, key)
    sync_tree(false)
    sync_runtime()
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
    app.update(demo.state, dt)
    sync_tree(false)
    sync_runtime()

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
        },
        runtime = demo.runtime,
        font_height = app.font_height,
        draw = false,
    })

    app.handle_messages(demo.state, demo.session:messages(), demo.layout)
    sync_tree(false)
    sync_runtime()

    collectgarbage("step", demo.gc_step_kb)
    update_memory_stats()
    reset_input_edges()
end

function love.draw()
    local w, h = love.graphics.getDimensions()

    love.graphics.clear(0.02, 0.04, 0.07, 1)
    demo.session:draw(demo.tree, {
        frame = current_frame(),
        runtime = demo.runtime,
        font_height = app.font_height,
    })

    love.graphics.setScissor()
    love.graphics.origin()
    love.graphics.setFont(demo.backend:get_font(4))
    love.graphics.setColor(0.55, 0.67, 0.82, 1)
    love.graphics.printf(
        string.format(
            "fps %d   mem %.1f MB (peak %.1f)   hovered %s   focused %s   tree builds %d   scene %d",
            love.timer.getFPS(),
            demo.mem_kb / 1024,
            demo.mem_peak_kb / 1024,
            tostring(demo.session.state.hot or "-"),
            tostring(demo.session.state.focused or "-"),
            demo.stats.rebuilds,
            demo.state.scene),
        0,
        h - 20,
        w - 16,
        "right")
end
