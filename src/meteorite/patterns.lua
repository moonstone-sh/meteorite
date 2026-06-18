local patterns = {}
local next_auto_id = 1

---@class MeteoritePatternInternal
---@field id string
---@field kind "pattern"
---@field name string
---@field type "pattern"
---@field pattern_id string
---@field ranges {integer, integer}[]
---@field min integer
---@field max integer
---@field report table

local function parse_size(value, default)
  if value == nil then return default end
  if type(value) == "number" then return value end
  local n, unit = tostring(value):match("^(%d+)%s*([kKmMgG]?[bB]?)$")
  assert(n, "invalid memory size: " .. tostring(value))
  n = tonumber(n)
  unit = unit:lower()
  if unit == "kb" or unit == "k" then return n * 1024 end
  if unit == "mb" or unit == "m" then return n * 1024 * 1024 end
  if unit == "gb" or unit == "g" then return n * 1024 * 1024 * 1024 end
  return n
end

local function parse_simple_bounded(pattern)
  local class, min, max = pattern:match("^%^%[([^%]]+)%]%{(%d+),(%d+)%}%$$")
  if not class then return nil end
  local ranges = {}
  local i = 1
  while i <= #class do
    local a = class:sub(i, i)
    if i + 2 <= #class and class:sub(i + 1, i + 1) == "-" then
      ranges[#ranges + 1] = { a:byte(), class:sub(i + 2, i + 2):byte() }
      i = i + 3
    else
      ranges[#ranges + 1] = { a:byte(), a:byte() }
      i = i + 1
    end
  end
  return { ranges = ranges, min = tonumber(min), max = tonumber(max) }
end

local function class_count_for(parsed)
  local count = 1
  for _, range in ipairs(parsed.ranges) do
    if range[1] == range[2] then count = count + 1 else count = count + 1 end
  end
  return count
end

local function auto_id()
  local id = "pattern_" .. tostring(next_auto_id)
  next_auto_id = next_auto_id + 1
  return id
end

---@param name? string
---@param source string
---@param opts? {max_dfa_states?: integer, max_dfa_bytes?: number|string}
---@return MeteoritePatternInternal
function patterns.define(name, source, opts)
  if source == nil then
    source = name
    name = nil
  end
  opts = opts or {}
  name = name or auto_id()
  local parsed = parse_simple_bounded(source)
  if not parsed then
    error("unsupported pattern syntax for " .. tostring(name) .. ": " .. tostring(source) .. "\nMeteorite Patterns v0.1 supports bounded ASCII classes like ^[a-z0-9_-]{1,64}$")
  end
  local class_count = class_count_for(parsed)
  local dfa_states = parsed.max + 2
  local state_width = 2
  local estimated = 256 + dfa_states * class_count * state_width + dfa_states
  local max_dfa_states = opts.max_dfa_states or 256
  local max_dfa_bytes = parse_size(opts.max_dfa_bytes, 32 * 1024)
  if dfa_states > max_dfa_states or estimated > max_dfa_bytes then
    error(table.concat({
      "pattern exceeded DFA budget",
      "",
      "pattern: " .. tostring(name),
      "max_dfa_bytes: " .. tostring(max_dfa_bytes),
      "generated_states: " .. tostring(dfa_states),
      "estimated_size: " .. tostring(estimated),
      "",
      "hint:",
      "  increase max_dfa_bytes",
      "  simplify alternation",
      "  use strategy = \"bounded_nfa\"",
    }, "\n"))
  end
  return {
    id = name,
    kind = "pattern",
    name = name,
    type = "pattern",
    pattern_id = name,
    ranges = parsed.ranges,
    min = parsed.min,
    max = parsed.max,
    report = {
      pattern = source,
      strategy = "class_dfa",
      input_bound = parsed.max,
      alphabet_classes = class_count,
      nfa_states = parsed.max + 1,
      dfa_states = dfa_states,
      transition_table_bytes = dfa_states * class_count * state_width,
      class_map_bytes = 256,
      estimated_bytes = estimated,
    },
  }
end

return patterns
