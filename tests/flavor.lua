package.path = "src/?.lua;src/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;tests/?.lua;" .. package.path

local flavor = require("meteorite.flavor")
local helpers = require("codegen.helpers")
local test = require("test")

-- Prefer the environment's real moonstone.variants (flavor-aware moon);
-- fall back to the vendored copy so this suite runs with an older moon.
local real_ok, real_variants = pcall(require, "moonstone.variants")
local variants = real_ok and real_variants or require("support.moonstone_variants")

local function with_variants(present, fn)
  local saved_loaded, saved_preload = package.loaded["moonstone.variants"], package.preload["moonstone.variants"]
  package.loaded["moonstone.variants"] = nil
  if present then
    package.preload["moonstone.variants"] = function() return variants end
  else
    package.preload["moonstone.variants"] = function() error("moonstone.variants unavailable") end
  end
  local ok, err = pcall(fn)
  package.loaded["moonstone.variants"] = saved_loaded
  package.preload["moonstone.variants"] = saved_preload
  if not ok then error(err, 0) end
end

local function tmp_root()
  local root = os.tmpname()
  os.remove(root)
  helpers.mkdir_p(root)
  return root
end

local function rm_rf(path)
  assert(os.execute("rm -rf " .. string.format("%q", path)))
end

local function touch(root, rel, content)
  local full = root .. "/" .. rel
  helpers.mkdir_p(full:match("^(.*)/[^/]+$"))
  helpers.write_file(full, content or ("-- " .. rel .. "\n"))
end

local lua54 = assert(flavor.parse_id("lua54-aarch64-macos"))
local luajit = assert(flavor.parse_id("luajit-x86_64-linux"))
local lua53 = assert(flavor.parse_id("lua53-x86_64-linux"))

test "flavor ids parse into Moonstone's target shape" (function()
  test.assert_eq(lua54.family, "lua", "family")
  test.assert_eq(lua54.level, 54, "level")
  test.assert_eq(lua54.os, "macos", "os")
  test.assert_eq(lua54.arch, "aarch64", "arch")
  test.assert_eq(luajit.family, "luajit", "luajit family")
  test.assert_eq(luajit.level, 51, "luajit level")
  test.assert_eq(luajit.id, "luajit-x86_64-linux", "id round trip")
  test.assert_eq(flavor.parse_id("lua6-x86_64-linux"), nil, "unknown language")
  test.assert_eq(flavor.parse_id("lua54"), nil, "missing os/arch")
end)

test "host flavor follows the running interpreter" (function()
  local host = flavor.host()
  if type(rawget(_G, "jit")) == "table" then
    test.assert_eq(host.family, "luajit", "luajit host")
  else
    local major, minor = _VERSION:match("(%d)%.(%d)")
    test.assert_eq(host.family, "lua", "puc family")
    test.assert_eq(host.level, tonumber(major .. minor), "puc level")
  end
end)

test "zig target triples replace os and arch, not the language" (function()
  local cross = flavor.for_zig_target(lua54, "x86_64-linux-gnu")
  test.assert_eq(cross.id, "lua54-x86_64-linux", "cross id")
  test.assert_eq(flavor.for_zig_target(lua54, "native"), lua54, "native keeps base")
  test.assert_eq(flavor.for_zig_target(lua54, nil), lua54, "nil keeps base")
end)

test "target flavor honors the override and the environment variables" (function()
  local restore = flavor.override_target(luajit)
  test.assert_eq((flavor.target()).id, "luajit-x86_64-linux", "override")
  restore()
  local lua = arg and arg[-1] or "lua"
  local cmd = "METEORITE_LUA_FLAVOR=lua51-riscv64-freebsd MOONSTONE_TARGET=lua54-x86_64-linux "
    .. string.format("%q", lua) .. " -e 'package.path=\"src/?.lua;\"..package.path; local f, s = require(\"meteorite.flavor\").target(); io.write(f.id, \" \", s)'"
  local pipe = assert(io.popen(cmd))
  local out = pipe:read("*a")
  pipe:close()
  test.assert_eq(out, "lua51-riscv64-freebsd METEORITE_LUA_FLAVOR", "graph-step variable wins")
  pipe = assert(io.popen("MOONSTONE_TARGET=lua53-x86_64-linux " .. string.format("%q", lua)
    .. " -e 'package.path=\"src/?.lua;\"..package.path; local f, s = require(\"meteorite.flavor\").target(); io.write(f.id, \" \", s)'"))
  out = pipe:read("*a")
  pipe:close()
  test.assert_eq(out, "lua53-x86_64-linux MOONSTONE_TARGET", "moonstone target next")
end)

test "without moonstone.variants files resolve to themselves" (function()
  with_variants(false, function()
    local root = tmp_root()
    touch(root, "src/app/x.lua")
    touch(root, "src/app/x@lua54.lua")
    test.assert_eq(flavor.variants(), nil, "no rule")
    test.assert_eq((flavor.resolve_file("src/app/x.lua", lua54, root)), "src/app/x.lua", "untagged path kept")
    local projected = flavor.project_files({ "a.lua", "a@lua54.lua" }, lua54)
    test.assert_eq(#projected, 2, "identity projection")
    test.assert_eq(flavor.install_searcher(), false, "searcher not installed")
    rm_rf(root)
  end)
end)

test "handler paths resolve to the most specific variant" (function()
  with_variants(true, function()
    local root = tmp_root()
    touch(root, "src/app/x.lua")
    touch(root, "src/app/x@lua54.lua")
    touch(root, "src/app/x@lua51.lua")
    touch(root, "src/app/x@luajit.lua")
    touch(root, "src/app/x@lua54@macos.lua")
    test.assert_eq((flavor.resolve_file("src/app/x.lua", lua54, root)), "src/app/x@lua54@macos.lua", "os beats language-only")
    test.assert_eq((flavor.resolve_file("src/app/x.lua", flavor.parse_id("lua54-x86_64-linux"), root)), "src/app/x@lua54.lua", "lua54 on linux")
    test.assert_eq((flavor.resolve_file("src/app/x.lua", luajit, root)), "src/app/x@luajit.lua", "luajit beats lua51")
    test.assert_eq((flavor.resolve_file("src/app/x.lua", lua53, root)), "src/app/x.lua", "untagged fallback")
    test.assert_eq((flavor.resolve_file("src/app/x@lua54.lua", lua53, root)), "src/app/x@lua54.lua", "explicit variant path is kept")
    test.assert_eq((flavor.resolve_file("src/app/missing.lua", lua54, root)), "src/app/missing.lua", "missing file unchanged")
    rm_rf(root)
  end)
end)

test "ambiguous variants fail; flavor-less modules stay absent" (function()
  with_variants(true, function()
    local root = tmp_root()
    touch(root, "src/fs@lua54.lua")
    touch(root, "src/fs@linux.lua")
    test.assert_error(function()
      flavor.resolve_file("src/fs.lua", flavor.parse_id("lua54-x86_64-linux"), root)
    end, "equally specific", "ambiguity")
    -- No matching variant and no untagged file: the module is absent for
    -- this flavor, so the declared (missing) path comes back unchanged.
    test.assert_eq((flavor.resolve_file("src/fs.lua", flavor.parse_id("lua53-aarch64-macos"), root)), "src/fs.lua", "absent module")
    rm_rf(root)
  end)
end)

test "projection collapses variants onto the plain module name" (function()
  with_variants(true, function()
    local projected = flavor.project_files({
      "lexlib/lexer.lua", "lexlib/lexer@lua54.lua", "lexlib/lexer@luajit.lua",
      "lexlib/only@luajit.lua", "lexlib/plain.lua", "lexlib/name@thing.lua",
    }, lua54)
    local by_path = {}
    for _, entry in ipairs(projected) do by_path[entry.path] = entry.source end
    test.assert_eq(by_path["lexlib/lexer.lua"], "lexlib/lexer@lua54.lua", "winner projected")
    test.assert_eq(by_path["lexlib/lexer@luajit.lua"], nil, "loser dropped")
    test.assert_eq(by_path["lexlib/only.lua"], nil, "absent for this flavor")
    test.assert_eq(by_path["lexlib/plain.lua"], "lexlib/plain.lua", "plain kept")
    test.assert_eq(by_path["lexlib/name@thing.lua"], "lexlib/name@thing.lua", "unrelated @ name is ordinary")
    test.assert_error(function()
      flavor.project_files({ "x@linux@lua54.lua" }, lua54)
    end, "language, os, arch order", "tag order")
  end)
end)

test "graph preparation points m.lua handlers at the target variant" (function()
  with_variants(true, function()
    local root = tmp_root()
    local output = root .. "/.meteorite/graph/current"
    helpers.mkdir_p(output)
    touch(root, "src/app/hello.lua", "return function(c) return c:text('fallback') end\n")
    touch(root, "src/app/hello@lua54.lua", "return function(c) return c:text('lua54') end\n")
    touch(root, "src/app/plain.lua", "return function(c) return c:text('plain') end\n")
    local prepare = require("codegen.graph_prepare")
    local function route(id, path)
      return { id = id, method = "GET", raw_path = "/" .. id, handler = { kind = "lua", path = path }, scope = {}, runtime = {}, execution = {} }
    end
    local hello, plain = route("hello", "src/app/hello.lua"), route("plain", "src/app/plain.lua")
    local restore = flavor.override_target(lua54)
    local ok, err = pcall(prepare.prepare_graph, { routes = { hello, plain } }, output, "hybrid")
    restore()
    if not ok then error(err, 0) end
    test.assert_eq(hello.handler.path, "src/app/hello@lua54.lua", "variant chosen")
    test.assert_eq(hello.handler.declared_path, "src/app/hello.lua", "declared path kept")
    test.assert_eq(hello.handler.flavor, "lua54-aarch64-macos", "flavor recorded")
    test.assert_eq(plain.handler.path, "src/app/plain.lua", "plain handler unchanged")
    test.assert_eq(plain.handler.declared_path, nil, "no provenance without a variant")

    local broken = route("broken", "src/app/broken.lua")
    touch(root, "src/app/broken@lua54.lua")
    touch(root, "src/app/broken@macos.lua")
    restore = flavor.override_target(lua54)
    ok, err = pcall(prepare.prepare_graph, { routes = { broken } }, output, "hybrid")
    restore()
    test.assert_true(not ok and tostring(err):find("handler `broken`", 1, true) ~= nil, "route named in error")
    rm_rf(root)
  end)
end)

test "hybrid release ships the selected module variant under its plain name" (function()
  with_variants(true, function()
    local graph = require("ballad.graph")
    local release_assets = require("ballad.release_assets")
    local root = tmp_root()
    touch(root, "src/app/hello@lua54.lua", "local util = require('app.util')\nreturn function(c) return c:text(util.name) end\n")
    touch(root, "src/app/hello.lua", "return function(c) return c:text('fallback') end\n")
    touch(root, "src/app/util.lua", "return { name = 'fallback' }\n")
    touch(root, "src/app/util@lua54.lua", "return { name = 'lua54' }\n")
    touch(root, "src/app/util@luajit.lua", "return { name = 'luajit' }\n")
    local app_graph = { routes = {
      { id = "hello", handler = { kind = "lua", path = "src/app/hello@lua54.lua" } },
    } }
    local assets = release_assets.new_set()
    release_assets.add_hybrid_lua_assets({ graph = graph.Graph.new() }, assets, root, app_graph, lua54)
    local by_virtual = {}
    for _, asset in ipairs(assets.assets) do by_virtual[asset.virtual_path] = asset end
    test.assert_true(by_virtual["src/app/hello@lua54.lua"] ~= nil, "resolved handler shipped at its loadfile path")
    local util = by_virtual["src/app/util.lua"]
    test.assert_true(util ~= nil, "module shipped under plain name")
    test.assert_true(util.source_path:find("util@lua54.lua", 1, true) ~= nil, "module content from the variant")
    test.assert_eq(util.metadata.flavor, "lua54-aarch64-macos", "flavor metadata")
    test.assert_eq(by_virtual["src/app/util@luajit.lua"], nil, "losing variant not shipped")

    -- Dependency trees (artifact files/share/lua) are projected too.
    touch(root, "artifact/files/share/lua/lexlib/lexer.lua")
    touch(root, "artifact/files/share/lua/lexlib/lexer@lua54.lua")
    touch(root, "artifact/files/share/lua/lexlib/lexer@luajit.lua")
    local pkg_assets = release_assets.new_set()
    release_assets.add_package_assets({ graph = graph.Graph.new() }, pkg_assets,
      { { kind = "lib", artifact_path = root .. "/artifact" } }, { flavor = luajit })
    test.assert_eq(#pkg_assets.assets, 1, "one projected module")
    test.assert_eq(pkg_assets.assets[1].virtual_path, "lua/lexlib/lexer.lua", "plain virtual path")
    test.assert_true(pkg_assets.assets[1].source_path:find("lexer@luajit.lua", 1, true) ~= nil, "luajit variant content")
    rm_rf(root)
  end)
end)

test.run()
