local path = require("ballad.path")
local release_assets = require("ballad.release_assets")
local release_contract = require("ballad.release_contract")

local tasks = {}

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return path.join(root, value)
end

function tasks.build_args_for(mode, opts)
  local args = {
    "build",
  }
  if opts.build_file then
    args[#args + 1] = "--build-file"
    args[#args + 1] = opts.build_file
  end
  args[#args + 1] = "install-server"
  args[#args + 1] = "-Dmode=" .. mode
  args[#args + 1] = "-Dgraph-input=" .. (opts.graph_input or "src/main.lua")
  args[#args + 1] = "-Dgraph-output=" .. (opts.graph_output or ".meteorite/graph/current")
  args[#args + 1] = "-Dbackend=" .. (opts.backend or "std_http")
  if opts.unix_socket_path or opts["unix-socket-path"] then args[#args + 1] = "-Dunix-socket-path=" .. (opts.unix_socket_path or opts["unix-socket-path"]) end
  if opts.unix_socket_mode or opts["unix-socket-mode"] then args[#args + 1] = "-Dunix-socket-mode=" .. (opts.unix_socket_mode or opts["unix-socket-mode"]) end
  if opts.unix_socket_unlink_stale ~= nil then args[#args + 1] = "-Dunix-socket-unlink-stale=" .. tostring(opts.unix_socket_unlink_stale) end
  if opts["unix-socket-unlink-stale"] ~= nil then args[#args + 1] = "-Dunix-socket-unlink-stale=" .. tostring(opts["unix-socket-unlink-stale"]) end
  args[#args + 1] = "-Dhybrid-profile=" .. (opts.hybrid_profile or opts["hybrid-profile"] or (mode == "release-hybrid" and "optimized" or "default"))
  args[#args + 1] = "-Drouter-dispatch=" .. (opts.router_dispatch or opts["router-dispatch"] or "param_matchers")
  if opts.project_root then args[#args + 1] = "-Dproject-root=" .. opts.project_root end
  if opts.meteorite_cli then args[#args + 1] = "-Dmeteorite-cli=" .. opts.meteorite_cli end
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
  -- The script runs with cwd=root, so pass output relative to root.
  -- source_payload_path may be relative to the Ballad process cwd; make it absolute.
  local source_arg = target_lua.source_payload_path
  if source_arg and source_arg ~= "" and source_arg:sub(1, 1) ~= "/" then
    local pipe = io.popen("pwd", "r")
    local cwd = (pipe:read("*l") or ""):gsub("/+$", "")
    pipe:close()
    source_arg = cwd .. "/" .. source_arg
  end
  return ctx:native_task({
    tool = "sh",
    args = { script, source_arg, output, target, opts.optimize or "ReleaseFast" },
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
  -- lua_root is relative to root; the script runs with cwd=root so pass it directly.
  -- If lua_root is absolute, pass as-is.
  local lua_root_arg = lua_root
  if lua_root_arg and lua_root_arg ~= "" and lua_root_arg:sub(1, 1) ~= "/" then
    -- Already relative to root, which is the cwd — pass directly
  end
  for _, package in ipairs(opts.packages or {}) do
    if release_assets.package_is_lua_cmodule(package) then
      local package_id = tostring(package.name or "package"):gsub("[^%w_.-]", "_")
      local output = path.join(".meteorite/release", target, "lua-cmodules", package_id)
      local output_path = join(root, output)
      -- Make source/rockspec paths absolute if relative (they are relative to Ballad process cwd)
      local function to_abs(p)
        if not p or p == "" or p:sub(1, 1) == "/" then return p end
        local pipe = io.popen("pwd", "r")
        local cwd = (pipe:read("*l") or ""):gsub("/+$", "")
        pipe:close()
        return cwd .. "/" .. p
      end
      outputs[#outputs + 1] = ctx:native_task({
        tool = "sh",
        args = { script, to_abs(package.source_payload_path), to_abs(package.rockspec_payload_path), lua_root_arg, output, target, package_id },
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
