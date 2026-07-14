local release_assets = require("ballad.release_assets")
local toml = require("ballad.toml")

local contract_mod = {}

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return root .. "/" .. value
end

local function file_exists(file_path)
  local f = io.open(file_path, "rb")
  if f then f:close(); return true end
  return false
end

local function read_file(file_path)
  local f = io.open(file_path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function hydrate_runtime_source_from_manifest(runtime)
  if type(runtime) ~= "table" then return runtime end
  if runtime.source_payload_path and runtime.source_payload_path ~= "" then return runtime end
  local artifact_path = runtime.artifact_path or runtime.path
  if not artifact_path or artifact_path == "" then return runtime end
  local manifest_path = runtime.manifest_path or join(artifact_path, "manifest.toml")
  local content = read_file(manifest_path)
  if not content then return runtime end
  local decoded = toml.parse(content)
  local origin = decoded and decoded.origin or {}
  local source_payload = origin.source_payload
  if source_payload and source_payload ~= "" then
    local source_payload_path = join(artifact_path, source_payload)
    if file_exists(source_payload_path) then
      runtime.source_payload = runtime.source_payload or source_payload
      runtime.source_payload_path = source_payload_path
      runtime.source_kind = runtime.source_kind or origin.source_kind
      runtime.source_hash = runtime.source_hash or ((decoded.artifact or {}).source_hash)
      runtime.manifest_path = manifest_path
    end
  end
  return runtime
end

function contract_mod.normalize_mode(mode)
  mode = mode or "hybrid"
  if mode == "hybrid" or mode == "release-hybrid" then return "release-hybrid", "hybrid" end
  if mode == "static" or mode == "release-static" then return "release-static", "static" end
  error("meteorite.release: unsupported mode `" .. tostring(mode) .. "`; expected hybrid or static")
end

function contract_mod.normalize_opts(opts)
  opts = opts or {}
  local project = opts.project or opts.moonstone_project
  if project then
    opts.root = opts.root or project.root
    opts.runtime = opts.runtime or hydrate_runtime_source_from_manifest(project.runtime)
    opts.packages = opts.packages or project.packages
    opts.target = opts.target or (project.runtime and project.runtime.target)
  end
  return opts
end

local function deployment_adapter(opts)
  return opts.adapter or opts.deployment_adapter or opts.runtime_adapter or opts.platform or opts.deploy_target
end

function contract_mod.validate_deployment_adapter(ctx, opts)
  local adapter = deployment_adapter(opts or {})
  if not adapter or adapter == "" or adapter == "binary" or adapter == "native" or adapter == "server" then return end
  local normalized = tostring(adapter):lower()
  if normalized == "serverless" or normalized == "edge" or normalized == "cloudflare" or normalized == "lambda" or normalized == "wasm" then
    ctx.fail(table.concat({
      "meteorite.release does not support `" .. tostring(adapter) .. "` deployment adapters in the current service-layer release.",
      "",
      "Meteorite currently emits a compiled binary server release directory, not a serverless function, edge worker, or WASM adapter artifact.",
      "",
      "Remediation: deploy the binary behind a proxy/CDN for edge routing, or choose adapter = 'binary' / omit adapter until serverless/edge adapter contracts are designed.",
    }, "\n"))
  end
  ctx.fail("meteorite.release: unsupported deployment adapter `" .. tostring(adapter) .. "`; expected binary/native/server")
end

local function source_at(item)
  local source = item and item.source or {}
  local file = source.file or source.short_src or "<unknown>"
  local line = source.line or source.linedefined or 0
  local column = source.column or 1
  return tostring(file) .. ":" .. tostring(line) .. ":" .. tostring(column)
end

local function add_lua_reference(refs, kind, label, item, hint)
  refs[#refs + 1] = {
    kind = kind,
    label = label,
    source = source_at(item),
    hint = hint,
  }
end

local function lua_references(graph)
  local refs = {}
  for _, route in ipairs(graph.routes or {}) do
    local handler = route.handler or {}
    if handler.kind == "inline_lua" then
      add_lua_reference(refs, "inline route handler", route.method .. " " .. route.raw_path, route, "move this handler to a Zig symbol/file or build with mode='hybrid'")
    elseif handler.kind == "lua" then
      add_lua_reference(refs, "Lua file/module route handler", route.method .. " " .. route.raw_path .. " -> " .. tostring(handler.path or handler.module), route, "replace with a Zig handler or build with mode='hybrid'")
    end
  end
  for _, plugin in ipairs(graph.plugins or {}) do
    if type(plugin.execute) == "function" then
      add_lua_reference(refs, "Lua scoped plugin", plugin.id or plugin.kind or "plugin", plugin, "expand this plugin to graph/Zig at construction time or build with mode='hybrid'")
    elseif plugin.handler and (plugin.handler.kind == "inline_lua" or plugin.handler.kind == "lua") then
      add_lua_reference(refs, "Lua scoped plugin", plugin.id or plugin.kind or "plugin", plugin, "replace with a graph/Zig plugin or build with mode='hybrid'")
    end
  end
  return refs
end

function contract_mod.for_graph(graph, release_mode)
  local refs = lua_references(graph)
  return {
    format = "ballad.release_contract.v0",
    validation_mode = release_mode,
    graph_may_be_produced_by_lua = true,
    retained_lua_nodes = refs,
    requires_target_lua = release_mode == "hybrid" and #refs > 0,
  }
end

function contract_mod.fail_static_lua(ctx, refs)
  if #refs == 0 then return end
  local lines = {
    "meteorite.release({ mode = 'static' }) failed the release compiler contract.",
    "",
    "The graph may be produced by Lua, but static mode cannot retain Lua runtime execution nodes.",
    "",
    "Lua runtime nodes found:",
  }
  for _, ref in ipairs(refs) do
    lines[#lines + 1] = "  - " .. ref.kind .. ": " .. ref.label
    lines[#lines + 1] = "    at: " .. ref.source
    lines[#lines + 1] = "    hint: " .. ref.hint
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Use meteorite.release({ mode = 'hybrid' }) to ship Lua, or remove/replace non-graphable Lua with Zig/graph-expanded handlers/plugins."
  ctx.fail(table.concat(lines, "\n"))
end

function contract_mod.assert_static_graph(ctx, graph)
  local refs = lua_references(graph or {})
  if #refs == 0 then return end
  local lines = {
    "meteorite.release({ mode = 'static' }) produced a graph with Lua runtime execution nodes after emission.",
    "",
    "This violates the static release contract and would require a Lua runtime at request time.",
    "",
    "Lua runtime nodes found:",
  }
  for _, ref in ipairs(refs) do
    lines[#lines + 1] = "  - " .. ref.kind .. ": " .. ref.label
    lines[#lines + 1] = "    at: " .. ref.source
    lines[#lines + 1] = "    hint: " .. ref.hint
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Remediation: build hybrid or replace retained Lua handlers/plugins with Zig/static graph nodes."
  ctx.fail(table.concat(lines, "\n"))
end

local function runtime_source_from_opts(opts)
  local runtime = opts.runtime or {}
  if opts.lua_source then return opts.lua_source, opts.lua_source_kind end
  if opts.runtime_source then return opts.runtime_source, opts.runtime_source_kind end
  if runtime.source_payload_path then return runtime.source_payload_path, runtime.source_kind end
  if runtime.source_payload then return runtime.source_payload, runtime.source_kind end
  if runtime.source then return runtime.source, runtime.source_kind end
  return os.getenv("METEORITE_LUA_SOURCE"), os.getenv("METEORITE_LUA_SOURCE_KIND")
end

local function runtime_field(opts, names)
  local runtime = opts.runtime or {}
  for _, name in ipairs(names) do
    if opts[name] then return opts[name] end
    if runtime[name] then return runtime[name] end
  end
  return nil
end

local function runtime_is_luajit(opts)
  local values = {
    runtime_field(opts, { "runtime_kind", "kind", "family", "runtime", "name", "id" }),
    runtime_field(opts, { "runtime_name", "runtime_id", "interpreter", "implementation" }),
    runtime_field(opts, { "version", "runtime_version" }),
  }
  for _, value in ipairs(values) do
    local text = tostring(value or ""):lower()
    if text:find("luajit", 1, true) then return true end
  end
  return false
end

local function runtime_source_is_rebuildable(source, kind)
  if not source or source == "" then return false end
  if not kind or kind == "" then return true end
  return kind == "source" or kind == "upstream_archive" or kind == "lua_source" or kind == "puc_lua_source"
end

local function package_label(package)
  return tostring(package.name or package.id or package.package or "<unknown>")
end

local function supported_cmodule_archive(source)
  source = tostring(source or "")
  return source:match("%.src%.rock$")
    or source:match("%.zip$")
    or source:match("%.tar%.gz$")
    or source:match("%.tgz$")
    or source:match("%.tar%.zst$")
    or source:match("%.tzst$")
    or source:match("%.tar%.xz$")
    or source:match("%.tar%.bz2$")
end

function contract_mod.target_from_opts(opts)
  local runtime = opts.runtime or {}
  return opts.target or runtime.target or runtime.abi_target
end

function contract_mod.is_cross_target(target)
  return target and target ~= "" and target ~= "native" and target ~= "any"
end

function contract_mod.validate_target_lua(ctx, root, contract, opts)
  if contract.validation_mode ~= "hybrid" then
    return { status = "not_required" }
  end
  local target = contract_mod.target_from_opts(opts)
  if not contract.requires_target_lua then
    return { status = "not_required", target = target }
  end

  local source, source_kind = runtime_source_from_opts(opts)
  if contract_mod.is_cross_target(target) and runtime_is_luajit(opts) then
    ctx.fail(table.concat({
      "meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) cannot cross-compile LuaJIT yet.",
      "",
      "Runtime:",
      "  " .. tostring(runtime_field(opts, { "runtime_kind", "kind", "family", "runtime", "name", "id" }) or "luajit"),
      "",
      "Reason:",
      "  LuaJIT requires a target matrix plus a host buildvm stage; Meteorite currently only rebuilds PUC Lua from upstream source archives with zig cc.",
      "",
      "Remediation:",
      "  use a PUC Lua runtime for cross-target hybrid releases, build same-host hybrid, or build static after replacing retained Lua runtime handlers/plugins.",
    }, "\n"))
  end
  if contract_mod.is_cross_target(target) and (not source or source == "") then
    local lines = {
      "meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) failed the release compiler contract.",
      "",
      "Hybrid mode may retain Lua runtime execution nodes, but cross-target release must materialize target Lua and target Lua modules.",
      "",
      "Target ABI:",
      "  " .. tostring(target),
      "",
      "Missing:",
      "  source_payload_path",
      "  source_kind/source provenance for the Lua runtime",
      "",
      "Lua runtime nodes found:",
    }
    for _, ref in ipairs(contract.retained_lua_nodes) do
      lines[#lines + 1] = "  - " .. ref.kind .. ": " .. ref.label
      lines[#lines + 1] = "    at: " .. ref.source
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Remediation: pass runtime = { source_payload_path = ..., source_kind = 'puc_lua_source' } from Moonstone/Ballad, set lua_source/runtime_source to an upstream Lua source archive, or build static after replacing Lua runtime handlers/plugins."
    ctx.fail(table.concat(lines, "\n"))
  end

  if contract_mod.is_cross_target(target) and not runtime_source_is_rebuildable(source, source_kind) then
    ctx.fail(table.concat({
      "meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) cannot build a transportable Lua runtime.",
      "",
      "Runtime payload:",
      "  source_payload_path: " .. tostring(source),
      "  source_kind: " .. tostring(source_kind),
      "  target_abi: " .. tostring(target),
      "",
      "Expected:",
      "  an upstream PUC Lua source archive, not a prebuilt Moonstone runtime artifact.",
      "",
      "Remediation:",
      "  pass meteorite.release({ runtime_source = <lua-source.tar.gz>, target = '" .. tostring(target) .. "' }) or publish Moonstone Lua runtime packages with source provenance.",
    }, "\n"))
  end

  if source and source ~= "" then
    local full = join(root, source)
    if not file_exists(full) then
      ctx.fail("meteorite.release({ mode = 'hybrid' }) runtime source_payload_path does not exist: " .. tostring(source))
    end
    return { status = contract_mod.is_cross_target(target) and "target_build_required" or "source_payload_available", target = target, source_payload_path = source, source_kind = source_kind }
  end

  return { status = "host_env", target = target }
end

function contract_mod.validate_packages(ctx, contract, opts)
  local root = opts.root or "."
  local target = contract_mod.target_from_opts(opts)
  if contract.validation_mode ~= "hybrid" or not contract.requires_target_lua or not contract_mod.is_cross_target(target) then return end
  for _, package in ipairs(opts.packages or {}) do
    if release_assets.package_is_lua_cmodule(package) then
      local label = package_label(package)
      if not package.source_payload_path or package.source_payload_path == "" then
        ctx.fail(table.concat({
          "meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) cannot rebuild Lua C module `" .. label .. "`.",
          "",
          "Missing:",
          "  package.source_payload_path",
          "",
          "Remediation: provide source provenance for this Lua C module package or remove it from the cross-target hybrid release.",
        }, "\n"))
      end
      if not package.rockspec_payload_path or package.rockspec_payload_path == "" then
        ctx.fail(table.concat({
          "meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) cannot rebuild Lua C module `" .. label .. "`.",
          "",
          "Missing:",
          "  package.rockspec_payload_path",
          "",
          "Remediation: provide the package rockspec provenance so Meteorite can rebuild the module for " .. tostring(target) .. ".",
        }, "\n"))
      end
      if not file_exists(join(root, package.source_payload_path)) then
        ctx.fail("meteorite.release({ mode = 'hybrid' }) Lua C module source_payload_path does not exist for `" .. label .. "`: " .. tostring(package.source_payload_path))
      end
      if not supported_cmodule_archive(package.source_payload_path) then
        ctx.fail(table.concat({
          "meteorite.release({ mode = 'hybrid' }) cannot rebuild Lua C module `" .. label .. "` from unsupported source archive.",
          "",
          "Source payload:",
          "  " .. tostring(package.source_payload_path),
          "",
          "Supported:",
          "  .src.rock, .zip, .tar.gz, .tgz, .tar.zst, .tzst, .tar.xz, .tar.bz2",
        }, "\n"))
      end
      if not file_exists(join(root, package.rockspec_payload_path)) then
        ctx.fail("meteorite.release({ mode = 'hybrid' }) Lua C module rockspec_payload_path does not exist for `" .. label .. "`: " .. tostring(package.rockspec_payload_path))
      end
    end
  end
end

return contract_mod
