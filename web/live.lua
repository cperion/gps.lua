local ws = require("web.ws")

local M = {}

local function remove_at(t, idx)
    table.remove(t, idx)
end

function M.hub(opts)
    local build_html = assert(opts.build_html, "web.live.hub: missing build_html(req)")
    local diff = assert(opts.diff, "web.live.hub: missing diff(old, new)")
    local encode = assert(opts.encode, "web.live.hub: missing encode(batch)")
    local normalize_request = opts.normalize_request or function(req) return req end
    local decode_message = opts.decode_message
    local on_message = opts.on_message
    local refresh_after_message = opts.refresh_after_message or false
    local broadcast_after_message = opts.broadcast_after_message or false
    local on_error = opts.on_error or function() end

    local hub = {
        _records = {},
    }

    local function find_record(conn)
        for i = 1, #hub._records do
            if hub._records[i].conn == conn then
                return hub._records[i], i
            end
        end
        return nil, nil
    end

    local function compile(req)
        local ok, result = xpcall(function()
            return build_html(req)
        end, debug.traceback)
        if not ok then
            on_error(result)
            return nil
        end
        return result
    end

    function hub:attach(conn, req)
        req = normalize_request(req)
        local html = compile(req)
        if html == nil then
            return nil
        end
        local record = {
            conn = conn,
            req = req,
            last_sent = html,
        }
        self._records[#self._records + 1] = record
        return record
    end

    function hub:record(conn)
        return find_record(conn)
    end

    function hub:detach(conn)
        local _, idx = find_record(conn)
        if idx ~= nil then
            remove_at(self._records, idx)
        end
    end

    function hub:count()
        return #self._records
    end

    function hub:set_request(conn, req)
        local record = find_record(conn)
        if not record then
            return false
        end
        record.req = normalize_request(req)
        return true
    end

    function hub:refresh(conn)
        local record = find_record(conn)
        if not record then
            return false
        end

        local new_html = compile(record.req)
        if new_html == nil then
            return false
        end

        local ok, batch = xpcall(function()
            return diff(record.last_sent, new_html)
        end, debug.traceback)
        if not ok then
            on_error(batch)
            return false
        end

        if #batch.ops > 0 then
            local payload_ok, payload = xpcall(function()
                return encode(batch)
            end, debug.traceback)
            if not payload_ok then
                on_error(payload)
                return false
            end
            local send_ok, send_err = xpcall(function()
                return record.conn:send_text(payload)
            end, debug.traceback)
            if not send_ok then
                on_error(send_err)
                self:detach(conn)
                return false
            end
        end

        record.last_sent = new_html
        return true
    end

    function hub:broadcast()
        for i = #self._records, 1, -1 do
            local record = self._records[i]
            if not self:refresh(record.conn) then
                local still = find_record(record.conn)
                if still == nil then
                    -- already detached by refresh
                end
            end
        end
    end

    function hub:dispatch(conn, text)
        local record = find_record(conn)
        if not record then
            return false
        end

        local message = text
        if decode_message then
            local ok, decoded = xpcall(function()
                return decode_message(text, record.req, conn, self, record)
            end, debug.traceback)
            if not ok then
                on_error(decoded)
                return false
            end
            message = decoded
        end

        if on_message then
            local ok, err = xpcall(function()
                return on_message(message, conn, record.req, self, record)
            end, debug.traceback)
            if not ok then
                on_error(err)
                return false
            end
        end

        if broadcast_after_message then
            self:broadcast()
        elseif refresh_after_message then
            self:refresh(conn)
        end

        return true
    end

    function hub:serve_ws(ws_opts)
        ws_opts = ws_opts or {}
        local request_builder = ws_opts.request or function(req) return req end
        local on_text = ws_opts.on_text
        local on_connect = ws_opts.on_connect
        local on_close = ws_opts.on_close

        return ws.serve({
            net = ws_opts.net,
            host = ws_opts.host,
            port = ws_opts.port,
            on_error = ws_opts.on_error or on_error,
            on_connect = function(conn, req)
                local app_req = request_builder(req)
                self:attach(conn, app_req)
                if on_text then
                    conn:on_text(function(text)
                        on_text(conn, app_req, text, self)
                    end)
                elseif decode_message or on_message then
                    conn:on_text(function(text)
                        self:dispatch(conn, text)
                    end)
                end
                if on_connect then
                    on_connect(conn, app_req, self)
                end
            end,
            on_close = function(conn)
                self:detach(conn)
                if on_close then
                    on_close(conn, self)
                end
            end,
        })
    end

    return hub
end

return M
