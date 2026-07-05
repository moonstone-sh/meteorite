---@meta

---@diagnostic disable: missing-return, lowercase-global

---@class MeteoriteContext_plain : MeteoriteContext

---@class MeteoriteContext_zig_static : MeteoriteContext

---@class MeteoriteContext_plain_static : MeteoriteContext

---@class MeteoriteContext_hybrid_zig : MeteoriteContext

---@class MeteoriteContext_bench_meta : MeteoriteContext

---@class MeteoriteContext_bench_raw : MeteoriteContext

---@class MeteoriteContext_bench_counters : MeteoriteContext

---@class MeteoriteContext_bench_stats_handler : MeteoriteContext

---@class MeteoriteContext_bench_stats_reset : MeteoriteContext

---@class MeteoriteContext_bench_fixture_info : MeteoriteContext

---@class MeteoriteContext_work_cpu_50us : MeteoriteContext

---@class MeteoriteContext_work_cpu_100us : MeteoriteContext

---@class MeteoriteContext_work_cpu_250us : MeteoriteContext

---@class MeteoriteContext_work_cpu_500us : MeteoriteContext

---@class MeteoriteContext_work_cpu_1ms : MeteoriteContext

---@class MeteoriteContext_work_cpu_2ms : MeteoriteContext

---@class MeteoriteContext_work_cpu_5ms : MeteoriteContext

---@class MeteoriteContext_work_sleep_1ms : MeteoriteContext

---@class MeteoriteContext_work_sleep_5ms : MeteoriteContext

---@class MeteoriteContext_work_sleep_10ms : MeteoriteContext

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

---@class MeteoriteContext_route_35 : MeteoriteContext

---@class MeteoriteContext_route_36 : MeteoriteContext

---@class MeteoriteContext_route_37 : MeteoriteContext

---@class MeteoriteContext_route_38 : MeteoriteContext

---@class MeteoriteParams_route_39
---@field id integer

---@class MeteoriteContext_route_39 : MeteoriteContext
---@field params MeteoriteParams_route_39

---@class MeteoriteParams_route_40
---@field id integer

---@class MeteoriteContext_route_40 : MeteoriteContext
---@field params MeteoriteParams_route_40

---@class MeteoriteParams_route_41
---@field id integer

---@class MeteoriteContext_route_41 : MeteoriteContext
---@field params MeteoriteParams_route_41

---@class MeteoriteContext_route_42 : MeteoriteContext

---@class MeteoriteContext_route_43 : MeteoriteContext

---@class MeteoriteContext_route_44 : MeteoriteContext

---@class MeteoriteContext_route_45 : MeteoriteContext

---@class MeteoriteParams_route_46
---@field id string

---@class MeteoriteContext_route_46 : MeteoriteContext
---@field params MeteoriteParams_route_46

---@class MeteoriteContext_route_47 : MeteoriteContext

---@class MeteoriteContext_route_48 : MeteoriteContext

---@class MeteoriteContext_route_49 : MeteoriteContext

---@class MeteoriteContext_route_50 : MeteoriteContext

---@class MeteoriteContext_route_51 : MeteoriteContext

---@class MeteoriteContext_route_52 : MeteoriteContext

---@class MeteoriteContext_route_53 : MeteoriteContext

---@class MeteoriteContext_route_54 : MeteoriteContext

---@class MeteoriteContext_route_55 : MeteoriteContext

---@class MeteoriteContext_route_56 : MeteoriteContext

---@class MeteoriteParams_route_57
---@field id integer

---@class MeteoriteContext_route_57 : MeteoriteContext
---@field params MeteoriteParams_route_57

---@class MeteoriteContext_route_58 : MeteoriteContext

---@class MeteoriteContext_route_59 : MeteoriteContext

---@class MeteoriteContext_route_60 : MeteoriteContext

---@class MeteoriteContext_route_61 : MeteoriteContext

---@class MeteoriteContext_route_62 : MeteoriteContext

---@class MeteoriteContext_route_63 : MeteoriteContext

---@class MeteoriteContext_route_64 : MeteoriteContext

---@class MeteoriteContext_route_65 : MeteoriteContext

---@class MeteoriteContext_route_66 : MeteoriteContext

---@class MeteoriteContext_route_67 : MeteoriteContext

---@class MeteoriteContext_route_68 : MeteoriteContext

---@class MeteoriteContext_route_69 : MeteoriteContext

---@class MeteoriteContext_route_70 : MeteoriteContext

---@class MeteoriteContext_route_71 : MeteoriteContext

---@class MeteoriteContext_route_72 : MeteoriteContext

---@class MeteoriteContext_route_73 : MeteoriteContext

---@class MeteoriteContext_route_74 : MeteoriteContext

---@class MeteoriteContext_route_75 : MeteoriteContext

