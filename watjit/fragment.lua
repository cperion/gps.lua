local Fragment = {}
Fragment.__index = Fragment

function Fragment.new()
    return setmetatable({
        lines = {},
        indent = 0,
    }, Fragment)
end

function Fragment:write(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    self.lines[#self.lines + 1] = string.rep("  ", self.indent) .. text
    return self
end

function Fragment:open(fmt, ...)
    self:write(fmt, ...)
    self.indent = self.indent + 1
    return self
end

function Fragment:close()
    self.indent = self.indent - 1
    return self:write(")")
end

function Fragment:emit(other)
    local prefix = string.rep("  ", self.indent)
    for i = 1, #other.lines do
        self.lines[#self.lines + 1] = prefix .. other.lines[i]
    end
    return self
end

function Fragment:source()
    return table.concat(self.lines, "\n")
end

Fragment.__tostring = Fragment.source

return setmetatable(Fragment, {
    __call = function()
        return Fragment.new()
    end,
})
