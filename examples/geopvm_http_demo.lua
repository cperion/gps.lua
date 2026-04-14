package.path = "./?.lua;./?/init.lua;" .. package.path

local geopvm = require("geopvm")

local store = geopvm.store.new({ tile_cache_size = 16, decode_cache_size = 16 })
geopvm.store.add_memory_layer(store, "demo", 3857, {})

local handler = geopvm.http.handler(store)

local function request(method, url, body)
    local req = { method = method, url = url, body = body }
    local res = {
        headers = {},
        statusCode = 0,
        setHeader = function(self, k, v) self.headers[k] = v end,
        finish = function(self, chunk) self.body = chunk end,
    }
    handler(req, res)
    print("==", method, url)
    print("status", res.statusCode)
    print(res.body or "")
    print()
end

request("POST", "/features/demo", [[
{"type":"Feature","id":"origin","geometry":{"type":"Point","coordinates":[0,0]},"properties":{"name":"Origin","n":1}}
]])

request("GET", "/query/demo?bbox=-1,-1,1,1")

request("PUT", "/features/demo/origin", [[
{"type":"Feature","id":"ignored","geometry":{"type":"Point","coordinates":[10,20]},"properties":{"name":"Moved"}}
]])

request("GET", "/query/demo?bbox=0,0,20,20")
request("DELETE", "/features/demo/origin")
request("GET", "/query/demo?bbox=0,0,20,20")
request("GET", "/health")
