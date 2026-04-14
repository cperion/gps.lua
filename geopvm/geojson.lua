-- geopvm/geojson.lua
--
-- Minimal GeoJSON serializer + parser for query/write responses.
--
-- v1 parser scope:
--   - Feature and FeatureCollection bodies
--   - Point / LineString / Polygon geometries
--   - flat scalar properties only (string/number/bool/null)
--
-- Coordinates are taken as-is. No reprojection is performed here.

local tonumber = tonumber
local tostring = tostring
local tconcat = table.concat

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("geopvm.asdl")
local json = require("json")
local jdec = require("json.decode")

local M = {}
local T = schema.T
M.T = T

local function json_string(s)
    s = s:gsub('\\', '\\\\')
         :gsub('"', '\\"')
         :gsub('\n', '\\n')
         :gsub('\r', '\\r')
         :gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function propvalue_json(v)
    if v == T.Geo.PNull then return "null" end
    local mt = classof(v)
    if mt == T.Geo.PStr then return json_string(v.v) end
    if mt == T.Geo.PNum then return tostring(v.v) end
    if mt == T.Geo.PBool then return v.v and "true" or "false" end
    error("unsupported prop value")
end

local function coords_json_raw(coords, start, len)
    local out = {}
    local stop = start + len - 1
    local k = 0
    for i = start, stop do
        local c = coords[i]
        k = k + 1
        out[k] = "[" .. c.x .. "," .. c.y .. "]"
    end
    return "[" .. tconcat(out, ",") .. "]"
end

local function geom_json(geom)
    local mt = classof(geom)
    if mt == T.Geo.Point then
        return '{"type":"Point","coordinates":[' .. geom.x .. ',' .. geom.y .. ']}'
    end
    if mt == T.Geo.LineString then
        local coords, start, len = geom:__raw_coords()
        return '{"type":"LineString","coordinates":' .. coords_json_raw(coords, start, len) .. '}'
    end
    if mt == T.Geo.Polygon then
        local rings = {}
        local ring_buf, ring_start, ring_len = geom:__raw_rings()
        local ring_stop = ring_start + ring_len - 1
        local k = 0
        for i = ring_start, ring_stop do
            local coords, start, len = ring_buf[i]:__raw_coords()
            k = k + 1
            rings[k] = coords_json_raw(coords, start, len)
        end
        return '{"type":"Polygon","coordinates":[' .. tconcat(rings, ",") .. ']}'
    end
    error("unsupported geometry")
end

local function props_json(props)
    local out = {}
    local entries, start, len = props:__raw_entries()
    local stop = start + len - 1
    local k = 0
    for i = start, stop do
        local prop = entries[i]
        k = k + 1
        out[k] = json_string(prop.key) .. ":" .. propvalue_json(prop.value)
    end
    return "{" .. tconcat(out, ",") .. "}"
end

function M.feature(feature)
    return '{"type":"Feature","id":' .. json_string(feature.id) ..
        ',"geometry":' .. geom_json(feature.geom) ..
        ',"properties":' .. props_json(feature.props) .. "}"
end

function M.feature_collection(features)
    local out = {}
    for i = 1, #features do
        out[i] = M.feature(features[i])
    end
    return '{"type":"FeatureCollection","features":[' .. tconcat(out, ",") .. "]}"
end

local function fail(msg)
    error("geopvm.geojson: " .. msg, 2)
end

local function id_from_json(v)
    if v == nil then
        fail("missing feature id")
    end
    local mt = classof(v)
    if mt == json.T.Json.Str then return v.v end
    if mt == json.T.Json.Num then return v.lexeme end
    fail("feature id must be string or number")
end

local function coord_from_json(v)
    local items = jdec.as_array(v)
    if #items < 2 then
        fail("coordinate must have at least two numbers")
    end
    return T.Geo.Coord(jdec.as_number(items[1]), jdec.as_number(items[2]))
end

local function coords_from_json(v)
    local items = jdec.as_array(v)
    local out = {}
    for i = 1, #items do
        out[i] = coord_from_json(items[i])
    end
    return out
end

local function rings_from_json(v)
    local items = jdec.as_array(v)
    local out = {}
    for i = 1, #items do
        out[i] = T.Geo.Ring(coords_from_json(items[i]))
    end
    return out
end

local function geometry_from_json(v)
    local typ = jdec.field_string(v, "type")
    local coords = jdec.require(v, "coordinates")
    if typ == "Point" then
        local c = coord_from_json(coords)
        return T.Geo.Point(c.x, c.y)
    end
    if typ == "LineString" then
        return T.Geo.LineString(coords_from_json(coords))
    end
    if typ == "Polygon" then
        return T.Geo.Polygon(rings_from_json(coords))
    end
    fail("unsupported geometry type '" .. tostring(typ) .. "'")
end

local function propvalue_from_json(v)
    if v == json.T.Json.Null then return T.Geo.PNull end
    local mt = classof(v)
    if mt == json.T.Json.Str then return T.Geo.PStr(v.v) end
    if mt == json.T.Json.Num then return T.Geo.PNum(tonumber(v.lexeme)) end
    if mt == json.T.Json.Bool then return T.Geo.PBool(v.v) end
    fail("property values must be scalar")
end

local function props_from_json(v)
    if v == nil or v == json.T.Json.Null then
        return schema.EMPTY_PROPS
    end
    local entries = jdec.as_object_entries(v)
    local out = {}
    for i = 1, #entries do
        local e = entries[i]
        out[i] = T.Geo.Prop(e.key, propvalue_from_json(e.value))
    end
    return T.Geo.Props(out)
end

function M.feature_from_json_value(v, forced_id)
    if jdec.field_string(v, "type") ~= "Feature" then
        fail("expected GeoJSON Feature")
    end
    local id = forced_id or id_from_json(jdec.get(v, "id"))
    local geom = geometry_from_json(jdec.require(v, "geometry"))
    local props = props_from_json(jdec.get(v, "properties"))
    return T.Geo.Feature(id, geom, props)
end

function M.features_from_json_value(v, forced_id)
    local typ = jdec.field_string(v, "type")
    if typ == "Feature" then
        return { M.feature_from_json_value(v, forced_id) }
    end
    if typ == "FeatureCollection" then
        local items = jdec.as_array(jdec.require(v, "features"))
        local out = {}
        for i = 1, #items do
            out[i] = M.feature_from_json_value(items[i])
        end
        return out
    end
    fail("expected Feature or FeatureCollection")
end

function M.feature_from_json_text(text, forced_id)
    return M.feature_from_json_value(json.parse_string(text), forced_id)
end

function M.features_from_json_text(text, forced_id)
    return M.features_from_json_value(json.parse_string(text), forced_id)
end

return M
