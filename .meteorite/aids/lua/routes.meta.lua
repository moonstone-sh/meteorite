---@meta

---@diagnostic disable: missing-return, lowercase-global

---@class MeteoriteContext_health : MeteoriteContext

---@class MeteoriteParams_get_user
---@field id integer

---@class MeteoriteContext_get_user : MeteoriteContext
---@field params MeteoriteParams_get_user

---@class MeteoriteParams_put_user
---@field id integer

---@class MeteoriteContext_put_user : MeteoriteContext
---@field params MeteoriteParams_put_user

---@class MeteoriteParams_patch_user
---@field id integer

---@class MeteoriteContext_patch_user : MeteoriteContext
---@field params MeteoriteParams_patch_user

---@class MeteoriteParams_delete_user
---@field id integer

---@class MeteoriteContext_delete_user : MeteoriteContext
---@field params MeteoriteParams_delete_user

---@class MeteoriteContext_echo : MeteoriteContext

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

---@class MeteoriteParams_email
---@field email string

---@class MeteoriteContext_email : MeteoriteContext
---@field params MeteoriteParams_email

---@class MeteoriteParams_token
---@field token string

---@class MeteoriteContext_token : MeteoriteContext
---@field params MeteoriteParams_token

---@class MeteoriteQuery_search
---@field exact boolean|nil
---@field page integer|nil
---@field q string

---@class MeteoriteContext_search : MeteoriteContext
---@field query MeteoriteQuery_search

---@class MeteoriteContext_route_15 : MeteoriteContext

