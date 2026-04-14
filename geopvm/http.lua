-- geopvm/http.lua
--
-- luvit-friendly HTTP adapter for the v1 skeleton.
--
-- This module avoids hard depending on luvit's `http` module until `serve()` is
-- called, so it can be required in plain Lua for tests.

local pvm = require("pvm")

local geojson = require("geopvm.geojson")
local store = require("geopvm.store")
local tile = require("geopvm.tile")

local M = {}

local function once(fn)
    local done = false
    return function(...)
        if done then return end
        done = true
        return fn(...)
    end
end

local function split_url(url)
    local path, query = url:match("^([^?]*)%??(.*)$")
    return path or url, query ~= "" and query or nil
end

local function parse_query_string(qs)
    local out = {}
    if not qs then return out end
    for key, value in qs:gmatch("([^&=?]+)=([^&=?]+)") do
        out[key] = value
    end
    return out
end

local function parse_bbox_param(s)
    if not s then return nil end
    local a, b, c, d = s:match("^([^,]+),([^,]+),([^,]+),([^,]+)$")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c), tonumber(d)
end

local function finish(res, code, body, content_type)
    body = body or ""
    if res.writeHead then
        res:writeHead(code, { ["Content-Type"] = content_type or "text/plain" })
        res:finish(body)
        return
    end
    if res.setHeader then
        res:setHeader("Content-Type", content_type or "text/plain")
    end
    if res.statusCode ~= nil then
        res.statusCode = code
    end
    res:finish(body)
end

local function read_body(req, cb)
    cb = once(cb)

    if req.body ~= nil then
        return cb(nil, req.body)
    end

    if type(req.readBody) == "function" then
        local ok, err = pcall(req.readBody, req, function(body)
            cb(nil, body or "")
        end)
        if not ok then cb(err) end
        return
    end

    if type(req.on) == "function" then
        local chunks = {}
        req:on("data", function(chunk)
            chunks[#chunks + 1] = chunk
        end)
        req:on("end", function()
            cb(nil, table.concat(chunks))
        end)
        req:on("error", function(err)
            cb(err)
        end)
        return
    end

    cb("request body unsupported")
end

local function error_status(err)
    local msg = tostring(err)
    if msg:find("unknown layer", 1, true) then
        return 404
    end
    return 400
end

function M.handler(store_state)
    return function(req, res)
        local method = req.method or "GET"
        local path, qs = split_url(req.url or "/")

        if method == "GET" and path == "/health" then
            local tile_cache = store_state.tile_cache:stats()
            local decode_cache = store_state.decode_cache:stats()
            local report = pvm.report_string(tile.phases)
            if report == "" then report = "  (no inner pvm phases in tile path)" end
            local body = table.concat({
                "ok\n",
                report, "\n",
                string.format("tile_cache size=%d hits=%d misses=%d evictions=%d\n",
                    tile_cache.size, tile_cache.hits, tile_cache.misses, tile_cache.evictions),
                string.format("decode_cache size=%d hits=%d misses=%d evictions=%d\n",
                    decode_cache.size, decode_cache.hits, decode_cache.misses, decode_cache.evictions),
            })
            return finish(res, 200, body, "text/plain")
        end

        if method == "GET" then
            local layer, z, x, y, fmt = path:match("^/tiles/([^/]+)/(%d+)/(%d+)/(%d+)%.([%a%d_%-]+)$")
            if layer and fmt == "mvt" then
                local bytes = tile.build_mvt(store_state, layer, tonumber(z), tonumber(x), tonumber(y))
                return finish(res, 200, bytes, "application/vnd.mapbox-vector-tile")
            end
        end

        if method == "GET" then
            local layer = path:match("^/query/([^/]+)$")
            if layer then
                local args = parse_query_string(qs)
                local minx, miny, maxx, maxy = parse_bbox_param(args.bbox)
                if not minx then
                    return finish(res, 400, "missing or invalid bbox", "text/plain")
                end
                local bbox = store.T.Geo.BBox(minx, miny, maxx, maxy)
                local features = store.query_bbox(store_state, layer, bbox)
                return finish(res, 200, geojson.feature_collection(features), "application/geo+json")
            end
        end

        if method == "POST" then
            local layer = path:match("^/features/([^/]+)$")
            if layer then
                return read_body(req, function(err, body)
                    if err then
                        return finish(res, 400, tostring(err), "text/plain")
                    end
                    local ok, result = pcall(function()
                        local features = geojson.features_from_json_text(body)
                        local ref
                        for i = 1, #features do
                            ref = store.put_feature(store_state, layer, features[i])
                        end
                        local payload = (#features == 1)
                            and geojson.feature(features[1])
                            or geojson.feature_collection(features)
                        return { ref = ref, payload = payload }
                    end)
                    if not ok then
                        return finish(res, error_status(result), tostring(result), "text/plain")
                    end
                    local ref, payload = result.ref, result.payload
                    return finish(res, 201, payload .. "\nrev=" .. tostring(ref.rev), "application/geo+json")
                end)
            end
        end

        if method == "PUT" then
            local layer, feature_id = path:match("^/features/([^/]+)/([^/]+)$")
            if layer and feature_id then
                return read_body(req, function(err, body)
                    if err then
                        return finish(res, 400, tostring(err), "text/plain")
                    end
                    local ok, result = pcall(function()
                        local feature = geojson.feature_from_json_text(body, feature_id)
                        local ref = store.put_feature(store_state, layer, feature)
                        return { ref = ref, feature = feature }
                    end)
                    if not ok then
                        return finish(res, error_status(result), tostring(result), "text/plain")
                    end
                    local ref, feature = result.ref, result.feature
                    return finish(res, 200,
                        geojson.feature(feature) .. "\nrev=" .. tostring(ref.rev),
                        "application/geo+json")
                end)
            end
        end

        if method == "DELETE" then
            local layer, feature_id = path:match("^/features/([^/]+)/([^/]+)$")
            if layer and feature_id then
                local ok, result = pcall(function()
                    local did_delete, layer_ref = store.delete_feature(store_state, layer, feature_id)
                    return { deleted = did_delete, ref = layer_ref }
                end)
                if not ok then
                    return finish(res, 404, tostring(result), "text/plain")
                end
                if result.deleted then
                    return finish(res, 200, "deleted\nrev=" .. tostring(result.ref.rev), "text/plain")
                end
                return finish(res, 404, "feature not found", "text/plain")
            end
        end

        return finish(res, 404, "not found", "text/plain")
    end
end

function M.serve(store_state, port, host)
    local http = require("http")
    local server = http.createServer(M.handler(store_state))
    server:listen(port or 8080, host or "0.0.0.0")
    return server
end

return M
