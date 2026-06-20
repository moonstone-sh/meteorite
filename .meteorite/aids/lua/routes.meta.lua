---@meta

---@diagnostic disable: missing-return, lowercase-global

---@class MeteoriteContext_plain : MeteoriteContext

---@class MeteoriteContext_plain_static : MeteoriteContext

---@class MeteoriteContext_hybrid_zig : MeteoriteContext

---@class MeteoriteContext_bench_meta : MeteoriteContext

---@class MeteoriteContext_bench_raw : MeteoriteContext

---@class MeteoriteContext_bench_counters : MeteoriteContext

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

---@class MeteoriteContext_hybrid_inline : MeteoriteContext

---@class MeteoriteContext_bench_hybrid_inline : MeteoriteContext

---@class MeteoriteContext_bench_hybrid_inline_text_literal : MeteoriteContext

---@class MeteoriteParams_hybrid_inline_params
---@field id integer

---@class MeteoriteContext_hybrid_inline_params : MeteoriteContext
---@field params MeteoriteParams_hybrid_inline_params

---@class MeteoriteContext_hybrid_inline_echo : MeteoriteContext

---@class MeteoriteContext_bench_unavailable_state : MeteoriteContext

---@class MeteoriteContext_bench_unavailable_global : MeteoriteContext

---@class MeteoriteContext_bench_unavailable_leak : MeteoriteContext

---@class MeteoriteContext_bench_unavailable_shared : MeteoriteContext

---@class MeteoriteContext_bench_unavailable_worker : MeteoriteContext

---@class MeteoriteContext_bench_unavailable_require : MeteoriteContext

