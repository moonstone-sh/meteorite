local path = require("ballad.path")
local release_assets = require("meteorite.release_assets")
local release_contract = require("meteorite.release_contract")

local tasks = {}

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return path.join(root, value)
end

function tasks.build_args_for(mode, opts)
  local args = {
    "build",
    "install-server",
    "-Dmode=" .. mode,
    "-Dgraph-input=" .. (opts.graph_input or "src/main.lua"),
    "-Dgraph-output=" .. (opts.graph_output or ".meteorite/graph/current"),
    "-Dbackend=" .. (opts.backend or "std_http"),
    "-Dhybrid-profile=" .. (opts.hybrid_profile or opts["hybrid-profile"] or (mode == "release-hybrid" and "optimized" or "default")),
    "-Drouter-dispatch=" .. (opts.router_dispatch or opts["router-dispatch"] or "param_matchers"),
  }
  if opts.optimize then args[#args + 1] = "-Doptimize=" .. opts.optimize end
  if opts.target then args[#args + 1] = "-Dtarget=" .. opts.target end
  if opts.lua_root then args[#args + 1] = "-Dlua-root=" .. opts.lua_root end
  args[#args + 1] = "--"
  args[#args + 1] = opts.output or opts.out or "dist/server"
  return args
end

function tasks.compile_target_lua(ctx, root, opts, target_lua, plugin_root)
  if not target_lua or target_lua.status ~= "target_build_required" then return nil end
  local target = target_lua.target
  local output = opts.target_lua_root or path.join(".meteorite/release", target, "lua")
  local output_path = join(root, output)
  local script = path.join(plugin_root, "scripts/build-target-lua.sh")
  return ctx:native_task({
    tool = "sh",
    args = { script, target_lua.source_payload_path, output_path, target, opts.optimize or "ReleaseFast" },
    cwd = root,
    outputs = { output_path },
    inputs = { target_lua.source_payload_path, script },
    cacheable = true,
    parallel_safe = false,
    description = "Build target Lua runtime for " .. tostring(target),
  }), output
end

function tasks.rebuild_lua_cmodules(ctx, root, opts, target_lua, lua_root, plugin_root)
  local target = release_contract.target_from_opts(opts)
  if not release_contract.is_cross_target(target) or not target_lua or not target_lua.source_payload_path then return {} end
  local outputs = {}
  local script = path.join(plugin_root, "scripts/build-lua-cmodule.sh")
  for _, package in ipairs(opts.packages or {}) do
    if release_assets.package_is_lua_cmodule(package) then
      local package_id = tostring(package.name or "package"):gsub("[^%w_.-]", "_")
      local output = path.join(".meteorite/release", target, "lua-cmodules", package_id)
      local output_path = join(root, output)
      outputs[#outputs + 1] = ctx:native_task({
        tool = "sh",
        args = { script, package.source_payload_path, package.rockspec_payload_path, join(root, lua_root), output_path, target, package_id },
        cwd = root,
        outputs = { output_path },
        inputs = { package.source_payload_path, package.rockspec_payload_path, script },
        cacheable = true,
        parallel_safe = false,
        description = "Rebuild Lua C module " .. tostring(package.name) .. " for " .. tostring(target),
      })
    end
  end
  return outputs
end

return tasks
