-- ui/init.lua
--
-- Public facade for the fresh UI stack.
--
-- This keeps the module graph explicit while still giving a convenient
-- `require("ui")` entrypoint.

local schema = require("ui.asdl")
local ds = require("ui.ds")
local lower = require("ui.lower")
local measure = require("ui.measure")
local hit = require("ui.hit")
local draw = require("ui.draw")
local session = require("ui.session")

local ui = {
    T = schema.T,
    schema = schema,

    asdl = schema,
    ds = ds,
    lower = lower,
    measure = measure,
    hit = hit,
    draw = draw,
    session = session,

    Session = session.Session,
    new_session = session.new,

    theme = ds.theme,
    surface = ds.surface,
    query = ds.query,
    resolve = ds.resolve,

    lower_node = lower.node,
    measure_node = measure.measure,
    hit_node = hit.hit,
    hit_id = hit.id,
    draw_node = draw.draw,
    record_node = draw.record,
    draw_paint = draw.paint,
    record_paint = draw.record_paint,

    frame = measure.frame,
    constraint = measure.constraint,
    exact = measure.exact,
    at_most = measure.at_most,
    available_constraint_from_frame = measure.available_constraint_from_frame,
    exact_constraint_from_frame = measure.exact_constraint_from_frame,

    DEFAULT_STYLE = ds.DEFAULT_STYLE,
    UNCONSTRAINED = measure.UNCONSTRAINED,
    NO_BASELINE = measure.NO_BASELINE,
    MISS = hit.MISS,
}

return ui
