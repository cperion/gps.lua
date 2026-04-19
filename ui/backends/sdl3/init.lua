local host = require("ui.backends.sdl3.host")
local runtime = require("ui.backends.sdl3.runtime")
local text = require("ui.backends.sdl3.text")
local ffi = require("ui.backends.sdl3.ffi")

return {
    name = "sdl3",
    ffi = ffi,
    host = host,
    runtime = runtime,
    text = text,
    new_host = host.new,
    poll_events = host.poll_events,
    filter_events = host.filter_events,
    partition_events = host.partition_events,
    new_text_system = text.new,
}
