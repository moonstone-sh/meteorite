package.path = "src/?.lua;src/?/init.lua;" .. package.path

local patterns = require("core.patterns")

local function simulate_match(p, input)
  if #input > p.max_len then return false end
  local state = p.start_state - 1
  local dead = p.dead_state - 1
  for i = 1, #input do
    local byte = input:byte(i)
    local class = p.class_map[byte + 1]
    local idx = state * p.class_count + class
    state = p.transitions[idx + 1]
    if state == dead then return false end
  end
  return p.accept[state + 1]
end

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg .. " expected=" .. tostring(expected) .. " got=" .. tostring(actual))
  end
end
local function assert_ok(pattern_source, input, expected, opts)
  local ok, p = pcall(patterns.define, "anon", pattern_source, opts or {})
  if not ok then
    failed = failed + 1
    print("FAIL: compile " .. pattern_source .. "\n" .. tostring(p))
    return
  end
  assert_eq(simulate_match(p, input), expected, pattern_source .. " | " .. input)
end
local function assert_error(pattern_source, expected_substring, opts)
  local ok, err = pcall(patterns.define, "anon", pattern_source, opts or {})
  if ok then
    failed = failed + 1
    print("FAIL: expected error for " .. pattern_source .. " but compiled")
    return
  end
  local s = tostring(err)
  if expected_substring and not s:find(expected_substring, 1, true) then
    failed = failed + 1
    print("FAIL: error missing '" .. expected_substring .. "' for " .. pattern_source .. "\n" .. s)
  else
    passed = passed + 1
  end
end

-- basic class and anchors
assert_ok("^[a-z]{1,64}$", "hello", true)
assert_ok("^[a-z]{1,64}$", "HELLO", false)
assert_ok("^[a-z]{1,64}$", "", false)
assert_ok("^[a-z]{1,64}$", string.rep("a", 65), false)
assert_ok("^[a-z]{1,64}$", string.rep("a", 64), true)
assert_ok("^[a-z0-9_-]{1,64}$", "foo_bar-1", true)

-- concatenation and literals
assert_ok("^[a-z]{1,64}@[a-z]{1,63}$", "user@examplecom", true)
assert_ok("^[a-z]{1,64}@[a-z]{1,63}$", "userexamplecom", false)

-- groups and bounded repetition
assert_ok("^[a-z]{1,64}@[a-z]{1,63}(\\.[a-z]{1,63}){1,8}$", "user@example.co", true, { max_dfa_states = 2048 })
assert_ok("^[a-z]{1,64}@[a-z]{1,63}(\\.[a-z]{1,63}){1,8}$", "user@example", false, { max_dfa_states = 2048 })

-- escaped special chars
assert_ok("^[a-z]+\\.[a-z]+$", "foo.bar", true, { max_len = 64 })

-- question mark quantifier
assert_ok("^a?b$", "b", true)
assert_ok("^a?b$", "ab", true)
assert_ok("^a?b$", "aab", false)

-- anchors only full-string
assert_error("foo$", "full-string anchored")
assert_error("^foo", "full-string anchored")

-- unsupported features
assert_error("^(?=foo).+$", "lookahead")
assert_error("^(.+)\\1$", "backreferences")
assert_error("^\\p{L}+$", "Unicode properties")
assert_error("^[a-z]+$", "max_len")
assert_error("^[a-z]*$", "max_len")
assert_error("^[^@]+$", "negated")
assert_error("^a|b$", "alternation")

-- plus and star work with max_len
assert_ok("^[a-z]+$", string.rep("a", 10), true, { max_len = 64 })
assert_ok("^[a-z]*$", "", true, { max_len = 64 })

-- email-like regex from the issue report
local email_source = "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@[A-Za-z0-9-]{1,63}(\\.[A-Za-z0-9-]{1,63}){1,8}$"
assert_ok(email_source, "user@example.com", true, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })
assert_ok(email_source, "a@b.co", true, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })
assert_ok(email_source, "first.last+tag@example.co", true, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })
assert_ok(email_source, "user_name@example-domain.com", true, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })
assert_ok(email_source, "@example.com", false, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })
assert_ok(email_source, "user@", false, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })
assert_ok(email_source, "user@example", false, { max_dfa_states = 2048, max_dfa_bytes = 128 * 1024 })

print("PASSED=" .. passed .. " FAILED=" .. failed)
if failed > 0 then os.exit(1) end
