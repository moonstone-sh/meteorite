--- Minimal test harness for Meteorite Lua tests.
--- Zero dependencies, works with Lua 5.4 and LuaJIT.
---
--- Usage:
---   local test = require("test")
---   test "zon encodes strings" (function()
---     test.assert_eq(zon.encode("hello"), '"hello"\n')
---   end)
---   test.run()

local M = {}

local tests = {}
local passed = 0
local failed = 0
local failures = {}

--- Register a test by name.
--- Usage: test "my test name" (function() ... end)
setmetatable(M, {
  __call = function(_, name, fn)
    if type(name) == "string" and type(fn) == "function" then
      tests[#tests + 1] = { name = name, fn = fn }
    elseif type(name) == "string" and fn == nil then
      -- Return a function that captures the name
      return function(f)
        tests[#tests + 1] = { name = name, fn = f }
      end
    end
    return M
  end,
})

function M.assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    local info = debug.getinfo(2, "Sl")
    local loc = (info.short_src or "?") .. ":" .. (info.currentline or 0)
    local m = msg and (" — " .. msg) or ""
    table.insert(failures, loc .. ": " .. m)
    print(string.format("  FAIL: %s\n    expected: %s\n    got:      %s", m, M._fmt(expected), M._fmt(actual)))
  end
end

function M.assert_true(value, msg)
  if value then
    passed = passed + 1
  else
    failed = failed + 1
    local info = debug.getinfo(2, "Sl")
    local loc = (info.short_src or "?") .. ":" .. (info.currentline or 0)
    local m = msg and (" — " .. msg) or "expected truthy"
    table.insert(failures, loc .. ": " .. m)
    print("  FAIL: " .. m)
  end
end

function M.assert_false(value, msg)
  M.assert_true(not value, msg or "expected falsy")
end

--- Assert that calling fn raises an error containing expected_substring.
function M.assert_error(fn, expected_substring, msg)
  local ok, err = pcall(fn)
  if ok then
    failed = failed + 1
    local m = msg or "expected error but function succeeded"
    print("  FAIL: " .. m)
    return
  end
  if expected_substring then
    local err_str = tostring(err)
    if not err_str:find(expected_substring, 1, true) then
      failed = failed + 1
      local m = (msg or "error mismatch") .. " — expected to contain '" .. expected_substring .. "'"
      print("  FAIL: " .. m .. "\n    got: " .. err_str)
      return
    end
  end
  passed = passed + 1
end

--- Deep table comparison.
function M.assert_table_eq(actual, expected, msg)
  if M._deep_eq(actual, expected) then
    passed = passed + 1
  else
    failed = failed + 1
    local m = msg or "tables not equal"
    print("  FAIL: " .. m .. "\n    expected: " .. M._fmt(expected) .. "\n    got:      " .. M._fmt(actual))
  end
end

function M._deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  -- Check all keys in a
  for k, v in pairs(a) do
    if not M._deep_eq(v, b[k]) then return false end
  end
  -- Check all keys in b (for missing keys in a)
  for k, _ in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function M._fmt(value)
  local t = type(value)
  if t == "nil" then return "nil" end
  if t == "string" then return string.format("%q", value) end
  if t == "number" or t == "boolean" then return tostring(value) end
  if t == "table" then
    local parts = {}
    for k, v in pairs(value) do
      parts[#parts + 1] = tostring(k) .. "=" .. M._fmt(v)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(value)
end

--- Run all registered tests and exit with appropriate code.
function M.run()
  local total = #tests
  for _, t in ipairs(tests) do
    io.write("  " .. t.name .. " ... ")
    io.flush()
    local ok, err = pcall(t.fn)
    if ok then
      print("ok")
    else
      failed = failed + 1
      print("ERROR")
      print("    " .. tostring(err))
    end
  end
  print(string.format("\n%d test(s), %d passed, %d failed", total, passed, failed))
  if failed > 0 then os.exit(1) end
end

--- Get current counts (for inline test files that don't use test.run())
function M.counts()
  return passed, failed
end

--- Print summary for inline-style tests
function M.summary()
  print("PASSED=" .. passed .. " FAILED=" .. failed)
  if failed > 0 then os.exit(1) end
end

return M
