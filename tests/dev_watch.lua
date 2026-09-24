package.path = "src/?.lua;src/?/init.lua;" .. package.path

local watch = require("core.dev_watch")

local policy = watch.normalize({
  graph = { "src/main.lua", "public", "src/main.lua", "runtime" },
  runtime = { "src/views", "src/loaders" },
  passive = { "src/client" },
  exclude = { "src/client" },
})
assert(table.concat(policy.graph, ",") == "public,runtime,src/main.lua")
assert(table.concat(policy.runtime, ",") == "src/loaders,src/views")
assert(table.concat(policy.passive, ",") == "src/client")
assert(table.concat(policy.exclude, ",") == "src/client")

local decoded = watch.decode(watch.encode(policy))
assert(table.concat(decoded.graph, ",") == table.concat(policy.graph, ","))
assert(table.concat(decoded.runtime, ",") == table.concat(policy.runtime, ","))
assert(table.concat(decoded.passive, ",") == table.concat(policy.passive, ","))
assert(watch.decode("meteorite.dev_watch.v1\n1\n0\nsrc/main.lua\n").graph[1] == "src/main.lua")

local meteorite = require("meteorite")
local app = meteorite.app({ name = "watch-test", dev_watch = {
  graph = { "src/main.lua" }, runtime = { "src/views" }, passive = { "src/client" }, exclude = { "src/client" },
} })
app:get("/health", "handlers.health")
local graph = app:normalize({ mode = "hybrid_dev" })
assert(graph.dev_watch.graph[1] == "src/main.lua")
assert(graph.dev_watch.runtime[1] == "src/views")
assert(graph.dev_watch.passive[1] == "src/client")
assert(graph.dev_watch.exclude[1] == "src/client")

local defaults = watch.normalize(nil)
assert(#defaults.graph > 0 and #defaults.runtime == 0)

for _, invalid in ipairs({ "/etc", "../outside", "src/../../outside", "src\nother", "src\\other", "src/*.lua", "-delete" }) do
  local ok = pcall(watch.normalize, { graph = { invalid } })
  assert(not ok, "accepted invalid watch path: " .. invalid)
end

print("dev watch policy: ok")
