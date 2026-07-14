package.path = "src/?.lua;src/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;tests/?.lua;;"

local test = require("test")
local release_contract = require("ballad.release_contract")

local retained_lua_contract = {
  validation_mode = "hybrid",
  requires_target_lua = true,
  retained_lua_nodes = {
    { kind = "inline route handler", label = "GET /health", source = "src/main.lua:1:1" },
  },
}

local function write_file(path, data)
  local file = assert(io.open(path, "wb"))
  file:write(data or "")
  file:close()
end

local function mkdir_p(path)
  assert(os.execute("mkdir -p " .. string.format("%q", path)))
end

local function ctx()
  return {
    fail = function(message) error(message, 0) end,
  }
end

test "binary deployment adapter is accepted" (function()
  release_contract.validate_deployment_adapter(ctx(), { adapter = "binary" })
  release_contract.validate_deployment_adapter(ctx(), { platform = "native" })
end)

test "serverless deployment adapter fails explicitly" (function()
  test.assert_error(function()
    release_contract.validate_deployment_adapter(ctx(), { adapter = "serverless" })
  end, "does not support `serverless` deployment adapters", "serverless diagnostic")
end)

test "edge deployment adapter diagnostic explains binary release" (function()
  test.assert_error(function()
    release_contract.validate_deployment_adapter(ctx(), { deployment_adapter = "edge" })
  end, "compiled binary server release directory", "edge diagnostic")
end)

test "unknown deployment adapter fails before release build" (function()
  test.assert_error(function()
    release_contract.validate_deployment_adapter(ctx(), { adapter = "workers" })
  end, "unsupported deployment adapter `workers`", "unknown adapter diagnostic")
end)

test "cross-target LuaJIT fails with explicit diagnostic" (function()
  test.assert_error(function()
    release_contract.validate_target_lua(ctx(), ".", retained_lua_contract, {
      target = "aarch64-linux-gnu",
      runtime = { kind = "luajit", version = "2.1" },
      runtime_source = "/tmp/not-used-for-luajit.tar.gz",
      runtime_source_kind = "luajit_source",
    })
  end, "cannot cross-compile LuaJIT yet", "luajit diagnostic")
end)

test "cross-target LuaJIT diagnostic mentions buildvm" (function()
  local ok, err = pcall(function()
    release_contract.validate_target_lua(ctx(), ".", retained_lua_contract, {
      target = "x86_64-linux-gnu",
      runtime = { implementation = "LuaJIT" },
      lua_source = "/tmp/not-used-for-luajit.tar.gz",
      lua_source_kind = "source",
    })
  end)
  test.assert_false(ok, "expected LuaJIT rejection")
  test.assert_true(tostring(err):find("buildvm", 1, true) ~= nil, "mentions buildvm")
  test.assert_true(tostring(err):find("PUC Lua", 1, true) ~= nil, "mentions PUC Lua alternative")
end)

test "same-host LuaJIT hybrid does not require cross-target rebuild" (function()
  local result = release_contract.validate_target_lua(ctx(), ".", retained_lua_contract, {
    target = "native",
    runtime = { kind = "luajit", version = "2.1" },
  })
  test.assert_eq(result.status, "host_env", "same-host status")
end)

test "project runtime source hydrates from Moonstone artifact manifest" (function()
  local root = os.tmpname()
  os.remove(root)
  mkdir_p(root .. "/sources")
  write_file(root .. "/sources/source.tar.gz", "lua source")
  write_file(root .. "/manifest.toml", table.concat({
    "[artifact]",
    'source_hash = "b3:source"',
    "",
    "[origin]",
    'source_kind = "puc_lua_source"',
    'source_payload = "sources/source.tar.gz"',
    "",
  }, "\n"))

  local opts = release_contract.normalize_opts({
    project = {
      root = ".",
      runtime = {
        name = "lua",
        version = "5.4.7",
        artifact_path = root,
      },
    },
  })

  test.assert_eq(opts.runtime.source_kind, "puc_lua_source", "source kind")
  test.assert_eq(opts.runtime.source_payload, "sources/source.tar.gz", "source payload")
  test.assert_eq(opts.runtime.source_payload_path, root .. "/sources/source.tar.gz", "source path")
  test.assert_eq(opts.runtime.source_hash, "b3:source", "source hash")
  test.assert_eq(opts.runtime.manifest_path, root .. "/manifest.toml", "manifest path")
end)

test "cross-target C module source payload must exist" (function()
  test.assert_error(function()
    release_contract.validate_packages(ctx(), retained_lua_contract, {
      root = ".",
      target = "aarch64-linux-gnu",
      packages = {
        { name = "missingcmodule", kind = "lua_cmodule", source_payload_path = "does/not/exist.tar.gz", rockspec_payload_path = "does/not/exist.rockspec" },
      },
    })
  end, "source_payload_path does not exist for `missingcmodule`", "missing source path")
end)

test "cross-target C module source archive extension is validated" (function()
  local source = "/tmp/meteorite-cmodule-source.unsupported"
  local rockspec = "/tmp/meteorite-cmodule.rockspec"
  write_file(source, "source")
  write_file(rockspec, "rockspec")
  test.assert_error(function()
    release_contract.validate_packages(ctx(), retained_lua_contract, {
      target = "aarch64-linux-gnu",
      packages = {
        { name = "badarchive", kind = "lua_cmodule", source_payload_path = source, rockspec_payload_path = rockspec },
      },
    })
  end, "unsupported source archive", "unsupported archive")
  os.remove(source)
  os.remove(rockspec)
end)

test "cross-target C module rockspec payload must exist" (function()
  local source = "/tmp/meteorite-cmodule-source.tar.gz"
  write_file(source, "source")
  test.assert_error(function()
    release_contract.validate_packages(ctx(), retained_lua_contract, {
      target = "aarch64-linux-gnu",
      packages = {
        { name = "norockspec", kind = "lua_cmodule", source_payload_path = source, rockspec_payload_path = "/tmp/meteorite-missing.rockspec" },
      },
    })
  end, "rockspec_payload_path does not exist for `norockspec`", "missing rockspec path")
  os.remove(source)
end)

test.run()
