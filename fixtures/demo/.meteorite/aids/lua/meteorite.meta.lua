---@class MeteoriteContext
---@field params table
---@field query table
---@field state table
local Context = {}

---@param body string
function Context:text(body) end

---@param value table|string|number|boolean
function Context:json(value) end

---@return string
function Context:body() end

---@param name string
function Context:http(name) end

---@param name string
function Context:auth(name) end

---@param name string
function Context:zig(name) end

---@param key string
function Context:get(key) end

---@param key string
---@param value any
function Context:set(key, value) end

---@class MeteoriteParams_route_3
---@field id integer

---@class MeteoriteContext_route_3 : MeteoriteContext
---@field params MeteoriteParams_route_3

---@class MeteoriteParams_route_5
---@field device_id string

---@class MeteoriteContext_route_5 : MeteoriteContext
---@field params MeteoriteParams_route_5

return Context
