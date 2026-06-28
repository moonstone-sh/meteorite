local patterns = {}
local next_auto_id = 1

local function auto_id()
  local id = "pattern_" .. tostring(next_auto_id)
  next_auto_id = next_auto_id + 1
  return id
end

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

-- Error helper with context
local function raise(source, pos, title, detail, hint)
  local line = source:sub(1, pos)
  local col = #line
  local snippet = source:sub(math.max(1, pos - 30), math.min(#source, pos + 30))
  error(table.concat({
    "error: " .. title,
    "",
    "pattern:",
    "  " .. source,
    "",
    "at position " .. tostring(pos) .. " (column " .. tostring(col) .. "):",
    "  ..." .. snippet:gsub("\n", "\\n") .. "...",
    "",
    detail and ("reason: " .. detail) or nil,
    "",
    hint and ("hint:\n" .. hint) or nil,
  }, "\n"))
end

local unsupported = {
  ["(?"]     = "lookahead/lookbehind/group modifiers",
  ["\\1"]    = "backreferences",
  ["\\2"]    = "backreferences",
  ["\\p{"]   = "Unicode properties",
  ["(?i"]    = "inline flags",
  ["(?s"]    = "inline flags",
  ["(?m"]    = "inline flags",
  ["\\b"]    = "word boundaries",
  ["*?"]     = "lazy quantifiers",
  ["+?"]     = "lazy quantifiers",
  ["}?"]     = "lazy quantifiers",
}

local function check_unsupported(source)
  for token, feature in pairs(unsupported) do
    local pos = source:find(token, 1, true)
    if pos then
      raise(source, pos, "unsupported Meteorite pattern syntax: " .. feature,
        "Meteorite Patterns v0.2 does not support " .. feature .. ".",
        "Use literals, anchored classes, bounded quantifiers, and simple groups instead.\nFor email validation, prefer m.email().")
    end
  end
  if source:find("[^", 1, true) then
    local pos = source:find("[^", 1, true)
    raise(source, pos, "unsupported Meteorite pattern syntax: negated character class",
      "Meteorite Patterns v0.2 does not support [^...] negated classes.",
      "Use an explicit positive class, or validate in a handler.")
  end
end

-- Lexer ----------------------------------------------------------------------
local Token = {}
Token.__index = Token

local function lexer(source)
  local pos = 1
  local tokens = {}

  local function peek(n) return source:sub(pos, pos + (n or 1) - 1) end
  local function advance(n) pos = pos + (n or 1) end
  local function emit(kind, value)
    tokens[#tokens + 1] = { kind = kind, value = value, pos = pos }
  end

  while pos <= #source do
    local ch = source:sub(pos, pos)
    if ch == "^" then emit("anchor_start", "^")
    elseif ch == "$" then emit("anchor_end", "$")
    elseif ch == "." then
      raise(source, pos, "unsupported Meteorite pattern syntax: dot wildcard",
        "The `.` wildcard is not supported because it is unbounded and ambiguous.",
        "Use an explicit character class like [a-zA-Z0-9] or [A-Za-z0-9.!#$%] for the exact bytes you want to match.")
    elseif ch == "(" then emit("lparen", "(")
    elseif ch == ")" then emit("rparen", ")")
    elseif ch == "{" then
      local rest = source:sub(pos)
      local min, max = rest:match("^{(%d+),(%d+)}")
      if min then
        local match_str = "{" .. min .. "," .. max .. "}"
        emit("quantifier", { min = tonumber(min), max = tonumber(max) })
        advance(#match_str)
      else
        local exact = rest:match("^{(%d+)}")
        if exact then
          local match_str = "{" .. exact .. "}"
          emit("quantifier", { min = tonumber(exact), max = tonumber(exact) })
          advance(#match_str)
        else
          raise(source, pos, "unsupported Meteorite pattern syntax: malformed quantifier",
            "Only bounded quantifiers like {n} or {min,max} are supported.",
            "Use {3} or {1,64}.")
        end
      end
    elseif ch == "}" then
      raise(source, pos, "unexpected '}'", "A closing brace must follow a valid {n} or {min,max} quantifier.", nil)
    elseif ch == "?" then emit("quantifier", { min = 0, max = 1 })
    elseif ch == "+" then emit("plus", "+")
    elseif ch == "*" then emit("star", "*")
    elseif ch == "[" then
      local start = pos
      advance(1)
      local negated = false
      if peek(1) == "^" then
        negated = true
        advance(1)
      end
      local chars = {}
      while pos <= #source do
        local c = source:sub(pos, pos)
        if c == "]" then break end
        if c == "\\" then
          advance(1)
          local esc = source:sub(pos, pos)
          if esc == "" then raise(source, pos, "unterminated escape", nil, nil) end
          if esc == "n" then chars[#chars + 1] = "\n"
          elseif esc == "t" then chars[#chars + 1] = "\t"
          elseif esc == "r" then chars[#chars + 1] = "\r"
          else chars[#chars + 1] = esc end
          advance(1)
        elseif c == "-" then
          -- literal dash if first or last in class
          chars[#chars + 1] = "-"
          advance(1)
        else
          chars[#chars + 1] = c
          advance(1)
        end
      end
      if source:sub(pos, pos) ~= "]" then
        raise(source, start, "unterminated character class", nil, "Close the class with ']'.")
      end
      advance(1)
      emit("class", { chars = chars, negated = negated, start = start })
    elseif ch == "\\" then
      advance(1)
      local esc = source:sub(pos, pos)
      if esc == "" then raise(source, pos, "unterminated escape", nil, nil) end
      if esc == "n" then emit("literal", "\n")
      elseif esc == "t" then emit("literal", "\t")
      elseif esc == "r" then emit("literal", "\r")
      else emit("literal", esc) end
      advance(1)
    else
      emit("literal", ch)
    end
    if ch ~= "{" and ch ~= "[" and ch ~= "\\" then advance(1) end
  end

  tokens[#tokens + 1] = { kind = "eof", value = nil, pos = pos }
  return tokens
end

-- Parser ----------------------------------------------------------------------
local Parser = {}
Parser.__index = Parser

local AST = {}
AST.Literal = function(byte) return { kind = "Literal", byte = byte } end
AST.Class = function(ranges) return { kind = "Class", ranges = ranges } end
AST.Concat = function(children) return { kind = "Concat", children = children } end
AST.Repeat = function(child, min, max) return { kind = "Repeat", child = child, min = min, max = max } end
AST.Group = function(child) return { kind = "Group", child = child } end
AST.Alternate = function(children) return { kind = "Alternate", children = children } end
AST.AnchorStart = function() return { kind = "AnchorStart" } end
AST.AnchorEnd = function() return { kind = "AnchorEnd" } end

local function class_from_chars(chars, source, start_pos)
  local ranges = {}
  local singles = {}
  local i = 1
  while i <= #chars do
    local a = chars[i]
    if i + 2 <= #chars and chars[i + 1] == "-" then
      local b = chars[i + 2]
      ranges[#ranges + 1] = { a:byte(), b:byte() }
      i = i + 3
    elseif i + 1 <= #chars and chars[i + 1] == "-" and i + 1 == #chars then
      -- trailing dash literal
      singles[a] = true
      i = i + 1
    else
      singles[a] = true
      i = i + 1
    end
  end
  for s in pairs(singles) do
    ranges[#ranges + 1] = { s:byte(), s:byte() }
  end
  table.sort(ranges, function(a, b) return a[1] < b[1] end)
  -- merge overlapping ranges
  local merged = {}
  for _, r in ipairs(ranges) do
    if #merged == 0 or r[1] > merged[#merged][2] + 1 then
      merged[#merged + 1] = { r[1], r[2] }
    else
      merged[#merged][2] = math.max(merged[#merged][2], r[2])
    end
  end
  if #merged == 0 then
    raise(source, start_pos, "empty character class", nil, "Add at least one character to the class.")
  end
  return merged
end

local function new_parser(tokens, source)
  local self = { tokens = tokens, pos = 1, source = source }
  return setmetatable(self, Parser)
end

function Parser:peek() return self.tokens[self.pos] end
function Parser:advance() self.pos = self.pos + 1 end
function Parser:expect(kind)
  local tok = self:peek()
  if not tok or tok.kind ~= kind then
    raise(self.source, tok and tok.pos or #self.source,
      "unexpected token in pattern",
      "expected: " .. kind .. ", got: " .. (tok and tok.kind or "eof"),
      nil)
  end
  self:advance()
  return tok
end

function Parser:parse_atom()
  local tok = self:peek()
  if tok.kind == "literal" then
    self:advance()
    if tok.value == "|" then
      raise(self.source, tok.pos, "unsupported Meteorite pattern syntax: alternation",
        "Meteorite Patterns v0.2 does not support | alternation yet.",
        "Split the route or validate alterzigs in a handler.")
    end
    return AST.Literal(tok.value:byte())
  elseif tok.kind == "class" then
    self:advance()
    if tok.value.negated then
      raise(self.source, tok.value.start, "unsupported Meteorite pattern syntax: negated character class",
        "[^...] is not supported.",
        "Use an explicit positive class or validate in a handler.")
    end
    return AST.Class(class_from_chars(tok.value.chars, self.source, tok.value.start))
  elseif tok.kind == "lparen" then
    self:advance()
    local inner = self:parse_alt()
    self:expect("rparen")
    return AST.Group(inner)
  elseif tok.kind == "anchor_start" then
    raise(self.source, tok.pos, "unexpected '^' inside pattern",
      "Anchors are only allowed at the start of the whole pattern.",
      "Use ^...$ to anchor the entire pattern.")
  elseif tok.kind == "anchor_end" then
    raise(self.source, tok.pos, "unexpected '$' inside pattern",
      "Anchors are only allowed at the end of the whole pattern.",
      "Use ^...$ to anchor the entire pattern.")
  else
    raise(self.source, tok.pos, "unexpected token in pattern",
      "got: " .. tok.kind,
      nil)
  end
end

function Parser:parse_quantified()
  local atom = self:parse_atom()
  while true do
    local tok = self:peek()
    if tok.kind == "quantifier" then
      self:advance()
      atom = AST.Repeat(atom, tok.value.min, tok.value.max)
    elseif tok.kind == "plus" or tok.kind == "star" then
      self:advance()
      local min = tok.kind == "plus" and 1 or 0
      atom = AST.Repeat(atom, min, math.huge)
    else
      break
    end
  end
  return atom, nil
end

function Parser:parse_seq()
  local children = {}
  while true do
    local atom, unbounded = self:parse_quantified()
    if unbounded then
      return children, unbounded
    end
    if not atom then break end
    children[#children + 1] = atom
    local tok = self:peek()
    if tok.kind == "rparen" or tok.kind == "anchor_end" or tok.kind == "eof" then
      break
    end
  end
  return children, nil
end

function Parser:parse_alt()
  local seq, unbounded = self:parse_seq()
  if unbounded then return nil, unbounded end
  if #seq == 0 then return AST.Concat({}), nil end
  local node = #seq == 1 and seq[1] or AST.Concat(seq)
  -- Check for alternation via | (pipe). We do not support it yet.
  local tok = self:peek()
  if tok.kind == "literal" and tok.value == "|" then
    raise(self.source, tok.pos, "unsupported Meteorite pattern syntax: alternation",
      "Meteorite Patterns v0.2 does not support | alternation yet.",
      "Split the route or validate alterzigs in a handler.")
  end
  return node, nil
end

function Parser:parse()
  local tok = self:peek()
  if tok.kind ~= "anchor_start" then
    raise(self.source, tok.pos, "Meteorite patterns must be full-string anchored",
      "expected pattern to start with '^'",
      "Use the form ^...$ to match the entire input.")
  end
  self:advance()

  local inner, unbounded = self:parse_alt()
  if unbounded then
    local q = unbounded.value
    local name = unbounded.kind == "plus" and "+" or "*"
    raise(self.source, unbounded.pos, "unbounded quantifier `" .. name .. "` requires max_len",
      "Meteorite Patterns v0.2 requires bounded patterns unless you supply max_len.",
      "Use:\n  m.pattern([[^[a-z]+$]], { max_len = 64 })\n\nor write:\n  m.pattern([[^[a-z]{1,64}$]])")
  end

  tok = self:peek()
  if tok.kind ~= "anchor_end" then
    raise(self.source, tok.pos, "Meteorite patterns must be full-string anchored",
      "expected pattern to end with '$'",
      "Use the form ^...$ to match the entire input.")
  end
  self:advance()

  tok = self:peek()
  if tok.kind ~= "eof" then
    raise(self.source, tok.pos, "unexpected token after pattern end",
      "got: " .. tok.kind,
      "Patterns must be exactly ^...$ with no trailing characters.")
  end

  local children = { AST.AnchorStart(), inner, AST.AnchorEnd() }
  return AST.Concat(children)
end

-- AST utilities ----------------------------------------------------------------
local function ast_max_len(node, max_len_override)
  if node.kind == "Concat" then
    local total = 0
    for _, c in ipairs(node.children) do
      total = total + ast_max_len(c, max_len_override)
    end
    return total
  elseif node.kind == "Literal" then
    return 1
  elseif node.kind == "Class" then
    return 1
  elseif node.kind == "Repeat" then
    return ast_max_len(node.child, max_len_override) * node.max
  elseif node.kind == "Group" then
    return ast_max_len(node.child, max_len_override)
  elseif node.kind == "AnchorStart" or node.kind == "AnchorEnd" then
    return 0
  elseif node.kind == "Alternate" then
    local max = 0
    for _, c in ipairs(node.children) do
      max = math.max(max, ast_max_len(c, max_len_override))
    end
    return max
  end
  return 0
end

-- NFA/DFA compiler ------------------------------------------------------------
local function epsilon_closure(states, nfa)
  local stack = {}
  local closure = {}
  for _, s in ipairs(states) do
    stack[#stack + 1] = s
    closure[s] = true
  end
  while #stack > 0 do
    local s = table.remove(stack)
    for _, t in ipairs(nfa[s].epsilon or {}) do
      if not closure[t] then
        closure[t] = true
        stack[#stack + 1] = t
      end
    end
  end
  return closure
end

local function nfa_to_dfa(nfa, classes, budget)
  local dfa_states = {}
  local dfa_transitions = {}
  local start_closure = epsilon_closure({1}, nfa)
  local start_key = {}
  for s in pairs(start_closure) do start_key[#start_key + 1] = s end
  table.sort(start_key)
  local start_sig = table.concat(start_key, ",")
  dfa_states[start_sig] = { id = 1, closure = start_closure, accept = false }
  local dfa_list = { dfa_states[start_sig] }
  local work = { start_sig }

  local function is_accept(closure)
    for s in pairs(closure) do
      if nfa[s].accept then return true end
    end
    return false
  end
  dfa_states[start_sig].accept = is_accept(start_closure)

  local class_count = #classes + 1 -- +1 for "other"

  while #work > 0 do
    local sig = table.remove(work, 1)
    local state = dfa_states[sig]
    dfa_transitions[state.id] = {}
    for class_idx, class in ipairs(classes) do
      local next_states = {}
      local seen = {}
      for s in pairs(state.closure) do
        local n = nfa[s]
        if n.trans and n.trans[class_idx] then
          for _, t in ipairs(n.trans[class_idx]) do
            if not seen[t] then
              seen[t] = true
              next_states[#next_states + 1] = t
            end
          end
        end
      end
      local closure = epsilon_closure(next_states, nfa)
      local key = {}
      for s in pairs(closure) do key[#key + 1] = s end
      table.sort(key)
      local nsig = table.concat(key, ",")
      if nsig == "" then
        dfa_transitions[state.id][class_idx] = 0 -- dead state
      else
        if not dfa_states[nsig] then
          if #dfa_list >= budget.states then
            return nil, "dfa state budget exceeded: " .. tostring(budget.states)
          end
          local id = #dfa_list + 1
          dfa_states[nsig] = { id = id, closure = closure, accept = is_accept(closure) }
          dfa_list[#dfa_list + 1] = dfa_states[nsig]
          work[#work + 1] = nsig
        end
        dfa_transitions[state.id][class_idx] = dfa_states[nsig].id
      end
    end
  end

  -- Add dead state transitions
  local dead = #dfa_list + 1
  dfa_transitions[dead] = {}
  for class_idx = 1, class_count do
    dfa_transitions[dead][class_idx] = dead
  end

  local accepts = {}
  for i = 1, dead do accepts[i] = dfa_list[i] and dfa_list[i].accept or false end

  return {
    state_count = dead,
    class_count = class_count,
    transitions = dfa_transitions,
    accept = accepts,
    start = 1,
    dead = dead,
  }
end

local function ast_to_nfa(ast)
  local nfa = {}
  local state_counter = 0
  local function new_state(accept)
    state_counter = state_counter + 1
    nfa[state_counter] = { accept = accept or false, trans = {}, epsilon = {} }
    return state_counter
  end

  local function compile(node, start, accept)
    if node.kind == "Literal" then
      local mid = new_state()
      nfa[start].trans[#nfa[start].trans + 1] = { byte = node.byte, target = mid }
      nfa[mid].epsilon[#nfa[mid].epsilon + 1] = accept
    elseif node.kind == "Class" then
      local mid = new_state()
      nfa[start].trans[#nfa[start].trans + 1] = { ranges = node.ranges, target = mid }
      nfa[mid].epsilon[#nfa[mid].epsilon + 1] = accept
    elseif node.kind == "Concat" then
      local prev = start
      for i, c in ipairs(node.children) do
        local is_last = (i == #node.children)
        local next_accept = is_last and accept or new_state()
        compile(c, prev, next_accept)
        prev = next_accept
      end
    elseif node.kind == "Repeat" then
      -- Unroll bounded repetition: chain max copies of the child NFA and allow
      -- accepting after min..max copies.  This keeps matching linear and avoids
      -- backtracking.
      local chain = { start }
      for i = 1, node.max do
        local entry = new_state()
        local exit_state = new_state()
        compile(node.child, entry, exit_state)
        nfa[chain[#chain]].epsilon[#nfa[chain[#chain]].epsilon + 1] = entry
        chain[#chain + 1] = exit_state
        if i >= node.min then
          nfa[exit_state].epsilon[#nfa[exit_state].epsilon + 1] = accept
        end
      end
      -- If min == 0, start can also accept (empty match).
      if node.min == 0 then
        nfa[start].epsilon[#nfa[start].epsilon + 1] = accept
      end
    elseif node.kind == "Group" then
      compile(node.child, start, accept)
    elseif node.kind == "AnchorStart" or node.kind == "AnchorEnd" then
      nfa[start].epsilon[#nfa[start].epsilon + 1] = accept
    elseif node.kind == "Alternate" then
      for _, c in ipairs(node.children) do
        local branch_start = new_state()
        local branch_accept = new_state()
        compile(c, branch_start, branch_accept)
        nfa[start].epsilon[#nfa[start].epsilon + 1] = branch_start
        nfa[branch_accept].epsilon[#nfa[branch_accept].epsilon + 1] = accept
      end
    end
  end

  local start = new_state()
  local accept = new_state(true)
  compile(ast, start, accept)
  return nfa, state_counter
end

local function byte_classes(ranges_list, literals)
  -- ranges_list is array of {ranges} from each class node.
  -- literals is array of literal byte values; each literal gets its own class
  -- segment so that literal transitions match exactly that byte.
  local boundaries = {}
  boundaries[1] = 0
  boundaries[2] = 256
  for _, ranges in ipairs(ranges_list) do
    for _, r in ipairs(ranges) do
      boundaries[#boundaries + 1] = r[1]
      if r[2] + 1 <= 256 then boundaries[#boundaries + 1] = r[2] + 1 end
    end
  end
  for _, b in ipairs(literals or {}) do
    boundaries[#boundaries + 1] = b
    if b + 1 <= 256 then boundaries[#boundaries + 1] = b + 1 end
  end
  table.sort(boundaries)
  local uniq = {}
  local last
  for _, b in ipairs(boundaries) do
    if b ~= last then
      last = b
      uniq[#uniq + 1] = b
    end
  end

  local segments = {}
  for i = 1, #uniq - 1 do
    segments[i] = { lo = uniq[i], hi = uniq[i + 1] - 1 }
  end

  -- assign class index for each segment
  local classes = {}
  for idx, seg in ipairs(segments) do
    classes[idx] = seg
  end
  return classes
end

local function class_index_for_byte(classes, byte)
  for i, seg in ipairs(classes) do
    if byte >= seg.lo and byte <= seg.hi then return i end
  end
  return #classes + 1 -- other/dead
end

local function remap_nfa_trans(nfa, classes)
  for _, state in ipairs(nfa) do
    local new_trans = {}
    for _, t in ipairs(state.trans or {}) do
      local targets = {}
      if t.byte then
        local idx = class_index_for_byte(classes, t.byte)
        targets[idx] = targets[idx] or {}
        table.insert(targets[idx], t.target)
      elseif t.ranges then
        for i, seg in ipairs(classes) do
          for _, r in ipairs(t.ranges) do
            if seg.lo <= r[2] and seg.hi >= r[1] then
              targets[i] = targets[i] or {}
              table.insert(targets[i], t.target)
              break
            end
          end
        end
      end
      for idx, list in pairs(targets) do
        new_trans[idx] = new_trans[idx] or {}
        for _, tgt in ipairs(list) do
          table.insert(new_trans[idx], tgt)
        end
      end
    end
    state.trans = new_trans
  end
  return nfa
end

local function bound_unbounded(node, source, max_len)
  if node.kind == "Repeat" and node.max == math.huge then
    if not max_len then
      local name = node.min == 0 and "*" or "+"
      raise(source, 1, "unbounded quantifier `" .. name .. "` requires max_len",
        "Meteorite Patterns v0.2 requires bounded patterns unless you supply max_len.",
        "Use:\n  m.pattern([[^[a-z]+" .. name .. "$]], { max_len = 64 })\n\nor write:\n  m.pattern([[^[a-z]{1,64}$]])")
    end
    node.max = max_len
  end
  if node.kind == "Concat" or node.kind == "Group" or node.kind == "Alternate" then
    for _, c in ipairs(node.children or {}) do bound_unbounded(c, source, max_len) end
  elseif node.kind == "Repeat" then
    bound_unbounded(node.child, source, max_len)
  end
end

local function compile_pattern(ast, source, name, opts)
  opts = opts or {}
  bound_unbounded(ast, source, opts.max_len)
  local max_input = opts.max_len or ast_max_len(ast)
  local nfa, nfa_states = ast_to_nfa(ast)
  local ranges_list = {}
  local literals = {}
  local function collect_ranges(node)
    if node.kind == "Class" then ranges_list[#ranges_list + 1] = node.ranges
    elseif node.kind == "Literal" then literals[#literals + 1] = node.byte
    elseif node.kind == "Concat" or node.kind == "Group" or node.kind == "Alternate" then
      for _, c in ipairs(node.children or {}) do collect_ranges(c) end
    elseif node.kind == "Repeat" then collect_ranges(node.child) end
  end
  collect_ranges(ast)
  local classes = byte_classes(ranges_list, literals)
  nfa = remap_nfa_trans(nfa, classes)

  local max_dfa_states = opts.max_dfa_states or 512
  local max_dfa_bytes = parse_size(opts.max_dfa_bytes, 32 * 1024)
  local dfa_budget = { states = max_dfa_states }
  local dfa, err = nfa_to_dfa(nfa, classes, dfa_budget)
  if not dfa then
    error(table.concat({
      "pattern exceeded DFA budget",
      "",
      "pattern: " .. tostring(source),
      "error: " .. tostring(err),
      "",
      "hint:",
      "  increase max_dfa_states or max_dfa_bytes",
      "  simplify the pattern",
      "  use a first-class validator like m.email()",
    }, "\n"))
  end

  local state_width = 2
  local transition_table_bytes = dfa.state_count * dfa.class_count * state_width
  local class_map_bytes = 256
  local estimated = class_map_bytes + transition_table_bytes + dfa.state_count

  if estimated > max_dfa_bytes then
    error(table.concat({
      "pattern exceeded DFA byte budget",
      "",
      "pattern: " .. tostring(source),
      "max_dfa_bytes: " .. tostring(max_dfa_bytes),
      "dfa_states: " .. tostring(dfa.state_count),
      "estimated_size: " .. tostring(estimated),
      "",
      "hint:",
      "  increase max_dfa_bytes",
      "  simplify the pattern",
      "  use a first-class validator like m.email()",
    }, "\n"))
  end

  -- Build class map
  local class_map = {}
  for b = 0, 255 do
    class_map[b + 1] = class_index_for_byte(classes, b) - 1 -- 0-based class index for emitter
  end

  -- Convert transitions to flat array [state][class] (0-based state ids for Zig)
  local transitions = {}
  for state = 1, dfa.state_count do
    for class = 1, dfa.class_count do
      local target = dfa.transitions[state][class]
      if target == 0 or target == nil then target = dfa.dead end
      transitions[#transitions + 1] = target - 1
    end
  end

  local accept = {}
  for state = 1, dfa.state_count do
    accept[state] = dfa.accept[state] and true or false
  end

  return {
    id = name,
    kind = "pattern",
    name = name,
    type = "pattern",
    pattern_id = name,
    ast = ast,
    max_len = max_input,
    nfa_states = nfa_states,
    dfa_states = dfa.state_count,
    class_count = dfa.class_count,
    class_map = class_map,
    transitions = transitions,
    accept = accept,
    start_state = 1,
    dead_state = dfa.dead,
    source = source,
    report = {
      pattern = source,
      strategy = "class_dfa",
      input_bound = max_input,
      alphabet_classes = dfa.class_count,
      nfa_states = nfa_states,
      dfa_states = dfa.state_count,
      transition_table_bytes = transition_table_bytes,
      class_map_bytes = class_map_bytes,
      estimated_bytes = estimated,
      linear_time = true,
      backtracking = false,
    },
  }
end

-- Public API ------------------------------------------------------------------
function patterns.define(name, source, opts)
  if source == nil then
    source = name
    name = nil
  end
  opts = opts or {}
  name = name or auto_id()

  check_unsupported(source)

  local tokens = lexer(source)
  local parser = new_parser(tokens, source)
  local ast = parser:parse()

  return compile_pattern(ast, source, name, opts)
end

return patterns
