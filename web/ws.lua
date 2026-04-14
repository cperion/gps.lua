local bit = require("bit")
local http = require("web.http")
local openssl = require("openssl")

local bxor = bit.bxor
local band = bit.band
local rshift = bit.rshift

local M = {}

local function websocket_accept(key)
    local hex = openssl.digest.digest("sha1", key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    return openssl.base64(openssl.hex(hex, false))
end

local function encode_frame(opcode, payload)
    payload = payload or ""
    local n = #payload
    if n < 126 then
        return string.char(0x80 + opcode, n) .. payload
    end
    if n < 65536 then
        local hi = math.floor(n / 256)
        local lo = n % 256
        return string.char(0x80 + opcode, 126, hi, lo) .. payload
    end
    error("web.ws: payload too large")
end

local function decode_masked(payload, mask1, mask2, mask3, mask4)
    local out = {}
    for i = 1, #payload do
        local m
        local slot = (i - 1) % 4
        if slot == 0 then m = mask1
        elseif slot == 1 then m = mask2
        elseif slot == 2 then m = mask3
        else m = mask4 end
        out[i] = string.char(bxor(payload:byte(i), m))
    end
    return table.concat(out)
end

local function parse_handshake(buffer)
    local term = buffer:find("\r\n\r\n", 1, true)
    if not term then
        return nil
    end

    local head = buffer:sub(1, term + 3)
    local rest = buffer:sub(term + 4)
    local line, headers_blob = head:match("^(.-)\r\n(.*)\r\n\r\n$")
    if not line then
        return false, "bad request", rest
    end

    local method, target = line:match("^(%S+)%s+(%S+)%s+HTTP/%d+%.%d+$")
    if method ~= "GET" then
        return false, "websocket requires GET", rest
    end

    local headers = {}
    for name, value in headers_blob:gmatch("([%w%-]+):%s*([^\r\n]+)") do
        headers[string.lower(name)] = value
    end

    local path, qs = http.split_url(target)
    return {
        method = method,
        target = target,
        path = path,
        query = http.parse_query_string(qs),
        headers = headers,
    }, nil, rest
end

local function parse_one_frame(buffer)
    local n = #buffer
    if n < 2 then
        return nil
    end

    local b1 = buffer:byte(1)
    local b2 = buffer:byte(2)
    local fin = band(b1, 0x80) ~= 0
    local opcode = band(b1, 0x0f)
    local masked = band(b2, 0x80) ~= 0
    local len = band(b2, 0x7f)
    local off = 3

    if not fin then
        return false, "fragmented frames are not supported"
    end

    if len == 126 then
        if n < 4 then
            return nil
        end
        len = buffer:byte(3) * 256 + buffer:byte(4)
        off = 5
    elseif len == 127 then
        return false, "64-bit websocket frames are not supported"
    end

    if masked then
        if n < off + 3 then
            return nil
        end
        local m1, m2, m3, m4 = buffer:byte(off, off + 3)
        off = off + 4
        if n < off + len - 1 then
            return nil
        end
        local payload = buffer:sub(off, off + len - 1)
        local rest = buffer:sub(off + len)
        return {
            opcode = opcode,
            payload = decode_masked(payload, m1, m2, m3, m4),
        }, nil, rest
    end

    if n < off + len - 1 then
        return nil
    end
    local payload = buffer:sub(off, off + len - 1)
    local rest = buffer:sub(off + len)
    return {
        opcode = opcode,
        payload = payload,
    }, nil, rest
end

function M.accept(socket, opts)
    opts = opts or {}

    local state = {
        buffer = "",
        open = false,
        closed = false,
        conn = nil,
    }

    local function really_close()
        if state.closed then
            return
        end
        state.closed = true
        if opts.on_close and state.conn then
            pcall(opts.on_close, state.conn)
        end
        if socket.destroy then
            socket:destroy()
        elseif socket.close then
            socket:close()
        end
    end

    local function safe_call(fn, ...)
        if not fn then
            return true
        end
        local argc = select("#", ...)
        local argv = { ... }
        local ok, err = xpcall(function()
            return fn(unpack(argv, 1, argc))
        end, debug.traceback)
        if not ok and opts.on_error then
            opts.on_error(err)
        end
        return ok, err
    end

    local conn = {}
    local text_handler = nil

    function conn:on_text(fn)
        text_handler = fn
    end

    function conn:send_text(payload)
        if state.closed then
            return false
        end
        socket:write(encode_frame(0x1, payload))
        return true
    end

    function conn:send_json(payload)
        return self:send_text(payload)
    end

    function conn:close()
        if state.closed then
            return
        end
        pcall(socket.write, socket, encode_frame(0x8, ""))
        really_close()
    end

    conn.socket = socket
    state.conn = conn

    local function handle_frame(frame)
        local opcode = frame.opcode
        if opcode == 0x1 then
            if text_handler then
                safe_call(text_handler, frame.payload)
            end
            return
        end
        if opcode == 0x8 then
            return really_close()
        end
        if opcode == 0x9 then
            pcall(socket.write, socket, encode_frame(0xA, frame.payload))
            return
        end
    end

    socket:on("data", function(chunk)
        state.buffer = state.buffer .. chunk

        if not state.open then
            local req, err, rest = parse_handshake(state.buffer)
            if req == nil and err == nil then
                return
            end
            if req == false then
                socket:write("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
                return really_close()
            end

            local key = req.headers["sec-websocket-key"]
            if not key then
                socket:write("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
                return really_close()
            end

            socket:write(
                "HTTP/1.1 101 Switching Protocols\r\n" ..
                "Upgrade: websocket\r\n" ..
                "Connection: Upgrade\r\n" ..
                "Sec-WebSocket-Accept: " .. websocket_accept(key) .. "\r\n\r\n"
            )

            state.buffer = rest
            state.open = true
            conn.request = req
            safe_call(opts.on_connect, conn, req)
        end

        while state.open and not state.closed do
            local frame, ferr, rest = parse_one_frame(state.buffer)
            if frame == nil and ferr == nil then
                return
            end
            if frame == false then
                if opts.on_error then
                    opts.on_error(ferr)
                end
                return really_close()
            end
            state.buffer = rest
            handle_frame(frame)
        end
    end)

    socket:on("error", function(err)
        if opts.on_error then
            opts.on_error(err)
        end
        really_close()
    end)
    socket:on("end", really_close)
    socket:on("close", really_close)

    return conn
end

function M.serve(opts)
    opts = opts or {}
    local net_mod = opts.net or require("net")
    local server = net_mod.createServer(function(socket)
        M.accept(socket, opts)
    end)
    server:listen(opts.port or 8081, opts.host or "0.0.0.0")
    return server
end

M.encode_text_frame = function(payload)
    return encode_frame(0x1, payload)
end

return M
