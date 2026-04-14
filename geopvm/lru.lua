-- geopvm/lru.lua
--
-- Small bounded LRU for request-space caches.

local M = {}

local function detach(self, node)
    local prev = node.prev
    local next = node.next
    if prev then prev.next = next else self.head = next end
    if next then next.prev = prev else self.tail = prev end
    node.prev = nil
    node.next = nil
end

local function attach_front(self, node)
    node.prev = nil
    node.next = self.head
    if self.head then
        self.head.prev = node
    else
        self.tail = node
    end
    self.head = node
end

local function evict_tail(self)
    local node = self.tail
    if not node then return nil end
    detach(self, node)
    self.map[node.key] = nil
    self.size = self.size - 1
    self.evictions = self.evictions + 1
    return node.key, node.value
end

local LRU = {}
LRU.__index = LRU

function LRU:get(key)
    local node = self.map[key]
    if not node then
        self.misses = self.misses + 1
        return nil
    end
    self.hits = self.hits + 1
    if node ~= self.head then
        detach(self, node)
        attach_front(self, node)
    end
    return node.value
end

function LRU:peek(key)
    local node = self.map[key]
    return node and node.value or nil
end

function LRU:set(key, value)
    if value == nil then
        return self:delete(key)
    end

    local node = self.map[key]
    if node then
        node.value = value
        if node ~= self.head then
            detach(self, node)
            attach_front(self, node)
        end
        return value
    end

    node = { key = key, value = value, prev = nil, next = nil }
    self.map[key] = node
    attach_front(self, node)
    self.size = self.size + 1

    while self.size > self.capacity do
        evict_tail(self)
    end

    return value
end

function LRU:delete(key)
    local node = self.map[key]
    if not node then return false end
    detach(self, node)
    self.map[key] = nil
    self.size = self.size - 1
    return true
end

function LRU:clear()
    self.map = {}
    self.head = nil
    self.tail = nil
    self.size = 0
end

function LRU:stats()
    return {
        capacity = self.capacity,
        size = self.size,
        hits = self.hits,
        misses = self.misses,
        evictions = self.evictions,
    }
end

function M.new(capacity)
    assert(type(capacity) == "number" and capacity >= 1, "lru capacity must be >= 1")
    return setmetatable({
        capacity = capacity,
        size = 0,
        map = {},
        head = nil,
        tail = nil,
        hits = 0,
        misses = 0,
        evictions = 0,
    }, LRU)
end

return M
