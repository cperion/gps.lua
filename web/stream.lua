local M = {}

local function nop() end

function M.consume(write, on_ready, g, p, c, on_done, on_error)
    on_done = on_done or nop
    on_error = on_error or nop

    if g == nil then
        on_done()
        return
    end

    local pumping = false

    local function pump()
        if pumping then
            return
        end
        pumping = true

        while true do
            local ok_step, next_c, chunk = pcall(g, p, c)
            if not ok_step then
                pumping = false
                on_error(next_c)
                return
            end

            if next_c == nil then
                pumping = false
                on_done()
                return
            end

            c = next_c

            local ok_write, writable = pcall(write, chunk)
            if not ok_write then
                pumping = false
                on_error(writable)
                return
            end

            if writable == false then
                pumping = false
                on_ready(pump)
                return
            end
        end
    end

    pump()
end

function M.luvit(res, g, p, c, on_done, on_error)
    return M.consume(
        function(chunk)
            return res:write(chunk)
        end,
        function(resume)
            if res.once then
                res:once("drain", resume)
                return
            end
            if res.on then
                local fired = false
                res:on("drain", function(...)
                    if fired then
                        return
                    end
                    fired = true
                    resume(...)
                end)
                return
            end
            resume()
        end,
        g, p, c,
        on_done,
        on_error
    )
end

return M
