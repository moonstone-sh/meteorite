---@meta

---@diagnostic disable: missing-return, lowercase-global

---@class MeteoriteAppOptions
---@field name? string
---@field profile? string|table

---@class MeteoriteRouteOptions
---@field params? table<string, MeteoriteSchemaValue>
---@field query? table<string, MeteoriteSchemaValue>
---@field body? {max?: number|string, [string]: any}
---@field memory? {max_body?: number|string, request_arena?: number|string}
---@field capabilities? table<string, any>

---@alias MeteoriteHandler string|fun(c: MeteoriteContext): any|{kind: string, module?: string, path?: string, symbol?: string, decl?: string}

---@class MeteoriteSchemaValue
---@field type string
---@field optional? boolean
---@field max_len? integer
---@field exact_len? integer
---@field pattern? MeteoritePattern

---@class MeteoritePattern : MeteoriteSchemaValue
---@field id string
---@field kind "pattern"
---@field pattern_id string

---@class MeteoriteApp
---@field name string
---@field routes table
---@field middleware table
---@field capabilities table<string, any>
---@field cache table
---@field get fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field get fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field use fun(self: MeteoriteApp, plugin_or_middleware: table|function, options?: table): MeteoriteApp
---@field capability fun(self: MeteoriteApp, kind: string, spec: table): MeteoriteApp
---@field get fun(self: MeteoriteApp, path: "/__bench/plain", handler: fun(c: MeteoriteContext_plain): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/plain", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_plain): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/zig-static", handler: fun(c: MeteoriteContext_zig_static): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/zig-static", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_zig_static): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/plain-static", handler: fun(c: MeteoriteContext_plain_static): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/plain-static", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_plain_static): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-zig", handler: fun(c: MeteoriteContext_hybrid_zig): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-zig", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_hybrid_zig): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/meta", handler: fun(c: MeteoriteContext_bench_meta): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/meta", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_bench_meta): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/raw", handler: fun(c: MeteoriteContext_bench_raw): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/raw", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_bench_raw): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/counters", handler: fun(c: MeteoriteContext_bench_counters): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/counters", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_bench_counters): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/stats", handler: fun(c: MeteoriteContext_bench_stats_handler): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/stats", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_bench_stats_handler): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/stats/reset", handler: fun(c: MeteoriteContext_bench_stats_reset): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/stats/reset", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_bench_stats_reset): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/fixture-info", handler: fun(c: MeteoriteContext_bench_fixture_info): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/fixture-info", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_bench_fixture_info): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/50us", handler: fun(c: MeteoriteContext_work_cpu_50us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/50us", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_50us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/100us", handler: fun(c: MeteoriteContext_work_cpu_100us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/100us", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_100us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/250us", handler: fun(c: MeteoriteContext_work_cpu_250us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/250us", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_250us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/500us", handler: fun(c: MeteoriteContext_work_cpu_500us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/500us", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_500us): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/1ms", handler: fun(c: MeteoriteContext_work_cpu_1ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/1ms", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_1ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/2ms", handler: fun(c: MeteoriteContext_work_cpu_2ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/2ms", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_2ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/5ms", handler: fun(c: MeteoriteContext_work_cpu_5ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/cpu/5ms", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_cpu_5ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/sleep/1ms", handler: fun(c: MeteoriteContext_work_sleep_1ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/sleep/1ms", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_sleep_1ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/sleep/5ms", handler: fun(c: MeteoriteContext_work_sleep_5ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/sleep/5ms", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_sleep_5ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/sleep/10ms", handler: fun(c: MeteoriteContext_work_sleep_10ms): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/work/sleep/10ms", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_work_sleep_10ms): any): table
---@field get fun(self: MeteoriteApp, path: "/health", handler: fun(c: MeteoriteContext_health): any): table
---@field get fun(self: MeteoriteApp, path: "/health", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_health): any): table
---@field get fun(self: MeteoriteApp, path: "/users/:id", handler: fun(c: MeteoriteContext_get_user): any): table
---@field get fun(self: MeteoriteApp, path: "/users/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_get_user): any): table
---@field put fun(self: MeteoriteApp, path: "/users/:id", handler: fun(c: MeteoriteContext_put_user): any): table
---@field put fun(self: MeteoriteApp, path: "/users/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_put_user): any): table
---@field patch fun(self: MeteoriteApp, path: "/users/:id", handler: fun(c: MeteoriteContext_patch_user): any): table
---@field patch fun(self: MeteoriteApp, path: "/users/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_patch_user): any): table
---@field delete fun(self: MeteoriteApp, path: "/users/:id", handler: fun(c: MeteoriteContext_delete_user): any): table
---@field delete fun(self: MeteoriteApp, path: "/users/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_delete_user): any): table
---@field post fun(self: MeteoriteApp, path: "/echo", handler: fun(c: MeteoriteContext_echo): any): table
---@field post fun(self: MeteoriteApp, path: "/echo", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_echo): any): table
---@field get fun(self: MeteoriteApp, path: "/devices/:device_id", handler: fun(c: MeteoriteContext_get_device): any): table
---@field get fun(self: MeteoriteApp, path: "/devices/:device_id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_get_device): any): table
---@field get fun(self: MeteoriteApp, path: "/files/:name", handler: fun(c: MeteoriteContext_file): any): table
---@field get fun(self: MeteoriteApp, path: "/files/:name", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_file): any): table
---@field get fun(self: MeteoriteApp, path: "/slugs/:slug", handler: fun(c: MeteoriteContext_slug): any): table
---@field get fun(self: MeteoriteApp, path: "/slugs/:slug", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_slug): any): table
---@field get fun(self: MeteoriteApp, path: "/uuids/:id", handler: fun(c: MeteoriteContext_uuid): any): table
---@field get fun(self: MeteoriteApp, path: "/uuids/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_uuid): any): table
---@field get fun(self: MeteoriteApp, path: "/hex/:digest", handler: fun(c: MeteoriteContext_hex): any): table
---@field get fun(self: MeteoriteApp, path: "/hex/:digest", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_hex): any): table
---@field get fun(self: MeteoriteApp, path: "/emails/:email", handler: fun(c: MeteoriteContext_email): any): table
---@field get fun(self: MeteoriteApp, path: "/emails/:email", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_email): any): table
---@field get fun(self: MeteoriteApp, path: "/tokens/:token", handler: fun(c: MeteoriteContext_token): any): table
---@field get fun(self: MeteoriteApp, path: "/tokens/:token", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_token): any): table
---@field get fun(self: MeteoriteApp, path: "/search", handler: fun(c: MeteoriteContext_search): any): table
---@field get fun(self: MeteoriteApp, path: "/search", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_search): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-empty", handler: fun(c: MeteoriteContext_route_35): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-empty", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_35): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-return-string", handler: fun(c: MeteoriteContext_route_36): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-return-string", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_36): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-text-direct", handler: fun(c: MeteoriteContext_route_37): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-text-direct", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_37): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-response-table", handler: fun(c: MeteoriteContext_route_38): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-response-table", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_38): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-direct-param/:id", handler: fun(c: MeteoriteContext_route_39): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-direct-param/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_39): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-ctx-param/:id", handler: fun(c: MeteoriteContext_route_40): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-ctx-param/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_40): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-req-table/:id", handler: fun(c: MeteoriteContext_route_41): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-req-table/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_41): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/lua-body-1k", handler: fun(c: MeteoriteContext_route_42): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/lua-body-1k", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_42): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-json-small", handler: fun(c: MeteoriteContext_route_43): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-json-small", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_43): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-state-counter", handler: fun(c: MeteoriteContext_route_44): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-state-counter", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_44): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-sleep-1s", handler: fun(c: MeteoriteContext_route_45): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-sleep-1s", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_45): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-echo-param/:id", handler: fun(c: MeteoriteContext_route_46): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-echo-param/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_46): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/lua-echo-body", handler: fun(c: MeteoriteContext_route_47): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/lua-echo-body", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_47): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-0", handler: fun(c: MeteoriteContext_route_48): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-0", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_48): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-10", handler: fun(c: MeteoriteContext_route_49): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-10", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_49): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-100", handler: fun(c: MeteoriteContext_route_50): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-100", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_50): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-1000", handler: fun(c: MeteoriteContext_route_51): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-1000", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_51): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-10000", handler: fun(c: MeteoriteContext_route_52): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-10000", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_52): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-100000", handler: fun(c: MeteoriteContext_route_53): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-loop-100000", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_53): any): table
---@field get fun(self: MeteoriteApp, path: "/hybrid-inline", handler: fun(c: MeteoriteContext_route_54): any): table
---@field get fun(self: MeteoriteApp, path: "/hybrid-inline", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_54): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-inline", handler: fun(c: MeteoriteContext_route_55): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-inline", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_55): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-inline-text-literal", handler: fun(c: MeteoriteContext_route_56): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-inline-text-literal", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_56): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-inline-params/:id", handler: fun(c: MeteoriteContext_route_57): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/hybrid-inline-params/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_57): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/hybrid-inline-echo", handler: fun(c: MeteoriteContext_route_58): any): table
---@field post fun(self: MeteoriteApp, path: "/__bench/hybrid-inline-echo", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_58): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/json/encode-small", handler: fun(c: MeteoriteContext_route_59): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/json/encode-small", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_59): any): table
---@field post fun(self: MeteoriteApp, path: "/__app/json/decode-1kb", handler: fun(c: MeteoriteContext_route_60): any): table
---@field post fun(self: MeteoriteApp, path: "/__app/json/decode-1kb", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_60): any): table
---@field post fun(self: MeteoriteApp, path: "/__app/json/roundtrip-1kb", handler: fun(c: MeteoriteContext_route_61): any): table
---@field post fun(self: MeteoriteApp, path: "/__app/json/roundtrip-1kb", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_61): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/template/hello", handler: fun(c: MeteoriteContext_route_62): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/template/hello", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_62): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/template/list-100", handler: fun(c: MeteoriteContext_route_63): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/template/list-100", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_63): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/sqlite/select-one", handler: fun(c: MeteoriteContext_route_64): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/sqlite/select-one", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_64): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/sqlite/select-100", handler: fun(c: MeteoriteContext_route_65): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/sqlite/select-100", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_65): any): table
---@field post fun(self: MeteoriteApp, path: "/__app/sqlite/insert-small", handler: fun(c: MeteoriteContext_route_66): any): table
---@field post fun(self: MeteoriteApp, path: "/__app/sqlite/insert-small", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_66): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/pipeline/cors", handler: fun(c: MeteoriteContext_route_67): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/pipeline/cors", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_67): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/pipeline/cors-json-template", handler: fun(c: MeteoriteContext_route_68): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/pipeline/cors-json-template", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_68): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/full/sqlite-json-template", handler: fun(c: MeteoriteContext_route_69): any): table
---@field get fun(self: MeteoriteApp, path: "/__app/full/sqlite-json-template", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_69): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-debug-state", handler: fun(c: MeteoriteContext_route_70): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-debug-state", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_70): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-global-counter", handler: fun(c: MeteoriteContext_route_71): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-global-counter", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_71): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-state-leak", handler: fun(c: MeteoriteContext_route_72): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-state-leak", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_72): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-shared-store", handler: fun(c: MeteoriteContext_route_73): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-shared-store", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_73): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-worker-store", handler: fun(c: MeteoriteContext_route_74): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-worker-store", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_74): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-require-cache", handler: fun(c: MeteoriteContext_route_75): any): table
---@field get fun(self: MeteoriteApp, path: "/__bench/lua-require-cache", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_route_75): any): table

---@class MeteoriteModule
---@field profiles table
---@field app fun(opts?: MeteoriteAppOptions): MeteoriteApp
---@field profile fun(name_or_table?: string|table, opts?: table): table
---@field string fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean, validate?: string|function|table, pattern?: MeteoritePattern}): MeteoriteSchemaValue
---@field slug fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field u64 fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field i32 fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field uuid fun(opts?: {optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field hex fun(opts?: {len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field email fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field token fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field bool fun(opts?: {optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field pattern fun(name_or_source: string, source_or_opts?: string|table, opts?: table): MeteoritePattern
---@field zig fun(path_or_symbol: string, opts?: {decl?: string}): table
---@field lua fun(module_ref: string): table
---@field file fun(path: string, opts?: table): table
---@field dir fun(root: string, opts?: table): table
---@field site fun(app: MeteoriteApp, opts: table): MeteoriteApp
---@type MeteoriteModule
local meteorite = {}

---@class MeteoriteContext
---@field params table<string, string|integer|number|boolean>
---@field query table<string, string|integer|number|boolean|nil>
---@field state table<string, any>
local Context = {}

---@param body string
function Context:text(body) end

---@param value table|string|number|boolean
---@param opts? {status?: integer}
function Context:json(value, opts) end

---@param status integer
---@param content_type string
---@param body string
function Context:bytes(status, content_type, body) end

---@return string
function Context:body() end

---@param name string
---@return MeteoriteHttpClient
function Context:http(name) end

---@param name string
---@return MeteoriteAuthClient
function Context:auth(name) end

---@param name string
---@return MeteoriteZigClient
function Context:zig(name) end

---@param key string
---@return any
function Context:get(key) end

---@param key string
---@param value any
function Context:set(key, value) end

---@class MeteoriteHttpClient
---@field get fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field post fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field put fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field patch fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field delete fun(self: MeteoriteHttpClient, path: string, opts?: table): table
local HttpClient = {}

---@class MeteoriteAuthClient
---@field headers fun(self: MeteoriteAuthClient): table<string, string>
local AuthClient = {}

---@class MeteoriteZigClient
---@field [string] function
local ZigClient = {}

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

---@class MeteoriteParams_route_46
---@field id string

---@class MeteoriteContext_route_46 : MeteoriteContext
---@field params MeteoriteParams_route_46

---@class MeteoriteParams_route_57
---@field id integer

---@class MeteoriteContext_route_57 : MeteoriteContext
---@field params MeteoriteParams_route_57

return meteorite
