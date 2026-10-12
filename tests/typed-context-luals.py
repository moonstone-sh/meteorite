#!/usr/bin/env python3
"""Check inferred request/response types with an actual LuaLS process."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
candidates = [os.environ.get("LUA_LS_PATH"), shutil.which("lua-language-server"),
              str(Path.home() / ".local/share/nvim/mason/bin/lua-language-server")]
server = next((path for path in candidates if path and Path(path).is_file()), None)
if not server:
    raise SystemExit("LuaLS is required: set LUA_LS_PATH or install lua-language-server")

with tempfile.TemporaryDirectory(prefix="meteorite-context-luals-") as directory:
    work = Path(directory)
    workspace = work / "workspace"
    (workspace / "src").mkdir(parents=True)
    generate = work / "generate.lua"
    generate.write_text('package.path = "src/?.lua;src/?/init.lua;" .. package.path\n' + r'''
local m = require("meteorite")
local contracts = m.contracts.from_document({format = "moonstone.contract-bundle.v1", exports = {{
  id = "todo.Create", input = {type = "object", additionalProperties = false,
    properties = {title = {type = "string"}, done = {type = "boolean"}}, required = {"title"}},
  output = {type = "object", additionalProperties = false,
    properties = {id = {type = "integer"}, title = {type = "string"}}, required = {"id", "title"}},
}}})
local app = m.app({name = "typed-context"})
app:post("/todos/:id", {params = {id = m.u64()}, json = contracts:input("todo.Create"), responses = {
  [201] = contracts:response("todo.Create"),
  [400] = {schema = {type = "object", properties = {error = {type = "string"}}, required = {"error"}, additionalProperties = false}},
}}, function(ctx) return ctx:json(201, {id = ctx.params.id, title = "test"}) end)
app:get("/health", {responses = {[200] = {schema = {type = "boolean"}}}}, function(ctx) return ctx:json(true) end)
require("codegen.luals_aids").emit(app:normalize({mode = "dev"}), arg[1] .. "/.meteorite/graph/current")
''')
    subprocess.run(["moon", "exec", "--", "lua", str(generate), str(workspace)], cwd=root, check=True)
    (workspace / ".luarc.json").write_text(json.dumps({
        "runtime": {"version": "Lua 5.4"},
        "workspace": {"library": [".meteorite/aids/lua"]},
        "diagnostics": {"disable": ["unused-local"]},
    }))
    (workspace / "src/good.lua").write_text('''local m = require("meteorite")
local app = m.app({name = "good"})
app:post("/todos/:id", function(ctx)
  local body, err = ctx:json_body()
  if not body then return ctx:json(400, {error = err or "invalid body"}) end
  ---@type string
  local title = body.title
  ---@type integer
  local id = ctx.params.id
  ---@type boolean|nil
  local done = body.done
  return ctx:json(201, {id = id, title = title})
end)
app:get("/health", function(ctx) return ctx:json(true) end)
''')
    (workspace / "src/bad.lua").write_text('''local m = require("meteorite")
m.app({name = "bad"}):post("/todos/:id", function(ctx)
  local body = ctx:json_body()
  if not body then return end
  ---@type boolean
  local title = body.title
  ctx:json(201, {id = "wrong", title = "test"})
  ctx:json(999, {id = 1, title = "test"})
  ctx:json({id = 1, title = "test"})
end)
''')
    report = work / "diagnostics.json"
    result = subprocess.run([server, "--check=" + str(workspace), "--check_format=json",
                             "--check_out_path=" + str(report), "--logpath=" + str(work / "log"),
                             "--metapath=" + str(work / "meta")], capture_output=True, text=True)
    assert report.exists(), result.stdout + result.stderr
    diagnostics = json.loads(report.read_text())
    good = [d for uri, items in diagnostics.items() if uri.endswith("/src/good.lua") for d in items]
    assert not good, good
    bad = [d for uri, items in diagnostics.items() if uri.endswith("/src/bad.lua") for d in items]
    lines = {d["range"]["start"]["line"] for d in bad}
    assert {5, 6, 7, 8} <= lines, bad
    assert {"assign-type-mismatch", "param-type-mismatch", "missing-parameter"} <= {d["code"] for d in bad}, bad
    print("PASS: LuaLS infers route bodies and params, checks responses/statuses, and accepts default-200 helpers")
