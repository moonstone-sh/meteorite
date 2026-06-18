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

---@class MeteoriteParams_get_user
---@field id integer

---@class MeteoriteContext_get_user : MeteoriteContext
---@field params MeteoriteParams_get_user

---@class MeteoriteParams_get_device
---@field device_id string

---@class MeteoriteContext_get_device : MeteoriteContext
---@field params MeteoriteParams_get_device

---@class MeteoriteParams_file
---@field name string

---@class MeteoriteContext_file : MeteoriteContext
---@field params MeteoriteParams_file

---@class MeteoriteParams_slug
---@field slug string

---@class MeteoriteContext_slug : MeteoriteContext
---@field params MeteoriteParams_slug

---@class MeteoriteParams_uuid
---@field id string

---@class MeteoriteContext_uuid : MeteoriteContext
---@field params MeteoriteParams_uuid

---@class MeteoriteParams_hex
---@field digest string

---@class MeteoriteContext_hex : MeteoriteContext
---@field params MeteoriteParams_hex

---@class MeteoriteQuery_search
---@field exact boolean|nil
---@field page integer|nil
---@field q string

---@class MeteoriteContext_search : MeteoriteContext
---@field query MeteoriteQuery_search

return Context
