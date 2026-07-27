--- Route contract and pipeline builder.
--- Defines the canonical route declaration shape and lowers all forms
--- (legacy signatures, canonical tables, pipeline functions) into a
--- single internal RouteContract with a pipeline of stages.
---
--- @class ContractModule
--- @field phases table<string,string>  Valid hook phases
--- @field kinds table<string,string>  Valid stage kinds
--- @field strategies table<string,string>  Valid strategies
--- @field valid_phases table<string,boolean>  Phase validation lookup
--- @field PipelineBuilder fun(route_id: string): PipelineBuilder  Create a pipeline builder
--- @field lower_handler_to_stage fun(handler: any): StageContract|nil, table|nil  Lower legacy handler to stage
--- @field validate_route_declaration fun(decl: table): string  Validate and return form ("canonical"|"legacy")
--- @field reject_unsupported_body_features fun(opts: table, route_label?: string): void  Reject body features outside the current release contract
--- @field build fun(method: string, decl: table, scope: table?): RouteContract  Build a RouteContract from any form
--- @field serialize fun(route_contract: RouteContract): table  Serialize for graph inspection

---@type ContractModule
--- Route contract and pipeline builder.
--- Defines the canonical route declaration shape and lowers all forms
--- (legacy signatures, canonical tables, pipeline functions) into a
--- single internal RouteContract with a pipeline of stages.
---
--- @class RouteContract
--- @field method string  HTTP method
--- @field route string  Raw path pattern  HTTP method
--- @field route string  Raw path pattern
--- @field id? string  Optional route identifier
--- @field name? string  Optional human-readable name
--- @field policy? table  Route-local policy table (consumed by plugins)
--- @field pipeline? StageContract[]  Ordered pipeline stages
--- @field hooks? HookContract[]  Explicit user hook escape hatches
--- @field meta? table  Arbitrary metadata
--- @field params? table  Path parameter validators
--- @field query? table  Query parameter validators
--- @field body? table  Body limits
--- @field memory? table  Memory/resource limits
--- @field capabilities? table  Capability requirements
--- @field scope? table  Mount scope chain
--- @field source? table  Source location info

local contract = {}
local hooks = require("core.hooks")

local function unsupported_multipart(route_label)
  local lines = {
    "Meteorite does not support multipart form parsing in the current service-layer release.",
    "",
    "Reason: multipart requires explicit per-route limits, temp-file policy, streaming/backpressure semantics, filename sanitization, and cleanup guarantees that are P1 design work rather than P0 release behavior.",
    "Hint: use raw ctx:body() with route body limits for small payloads, or put uploads behind an external upload service until the multipart parser contract is implemented.",
  }
  if route_label then table.insert(lines, 2, "route: " .. route_label) end
  error(table.concat(lines, "\n"))
end

function contract.reject_unsupported_body_features(opts, route_label)
  if type(opts) ~= "table" then return end
  if opts.multipart ~= nil or opts.multipart_body ~= nil then
    unsupported_multipart(route_label)
  end
  if type(opts.body) == "table" and opts.body.multipart ~= nil then
    unsupported_multipart(route_label)
  end
end

--- @class StageContract
--- @field id? string  Stage identifier (must be unique within route)
--- @field kind string  transform | handle | hook
--- @field phase? string  Hook phase (required for kind=hook)
--- @field strat string  inline_lua | lua | zig | rust
--- @field path? string  External file path (for lua/zig/rust)
--- @field symbol? string  Zig symbol name (for strat=zig)
--- @field fn_ref? function  Inline Lua function reference
--- @field reads? string[]  Declared state reads
--- @field writes? string[]  Declared state writes
--- @field may_short_circuit? boolean  Whether this stage can short-circuit
--- @field meta? table  Arbitrary metadata
--- @field owner? string  Plugin id that injected this stage
--- @field source? table  Source location info

--- @class HookContract
--- @field phase string  pre_tree | post_match | pre_handler | post_handler | observe | error
--- @field owner_plugin? string  Plugin id
--- @field route_id? string  Route id (nil for global hooks)
--- @field stage StageContract  The hook stage

--- Hook phases
contract.phases = {
  pre_tree = "pre_tree",
  post_match = "post_match",
  pre_handler = "pre_handler",
  post_handler = "post_handler",
  observe = "observe",
  error = "error",
}

--- Valid stage kinds
contract.kinds = {
  transform = "transform",
  handle = "handle",
  hook = "hook",
}

--- Valid strategies
contract.strategies = {
  inline_lua = "inline_lua",
  lua = "lua",
  zig = "zig",
  rust = "rust",
}

--- Valid hook phases
contract.valid_phases = {
  pre_tree = true,
  post_match = true,
  pre_handler = true,
  post_handler = true,
  observe = true,
  error = true,
}

local before_handle_phases = {
  pre_tree = true,
  post_match = true,
  pre_handler = true,
}

local after_handle_phases = {
  post_handler = true,
  observe = true,
  error = true,
}

-- ============================================================
-- Source location helpers
-- ============================================================

local function source_info(level)
  local info = debug.getinfo(level or 3, "Sl") or {}
  local file = info.short_src or info.source or "?"
  if file:sub(1, 1) == "@" then file = file:sub(2) end
  return { file = file, line = info.currentline or 0, column = 1 }
end

-- ============================================================
-- PipelineBuilder
-- ============================================================

--- @class PipelineBuilder
--- @field stages StageContract[]  Recorded stages
--- @field _building boolean  Whether currently in build mode
--- @field _route_id string  Route id for diagnostics

--- Create a new pipeline builder.
--- Passed as `ctx` to the `pipeline = function(ctx) ... end` callback.
--- Create a new pipeline builder.
--- Passed as `ctx` to the `pipeline = function(ctx) ... end` callback.
---@param route_id string  Route id for diagnostics
---@return PipelineBuilder
local function PipelineBuilder(route_id)
  local builder = {
    stages = {},
    _building = true,
    _route_id = route_id or "<unknown>",
  }

  --- Normalize a stage argument into a StageContract.
  local function normalize_stage(kind, ...)
    local args = { ... }
    local stage

    if type(args[1]) == "table" and args[1].strat ~= nil then
      -- Explicit table form: ctx:transform({ id = "...", strat = "lua", path = "..." })
      stage = args[1]
      stage.kind = kind
    elseif type(args[1]) == "function" then
      -- Inline Lua function: ctx:transform(function(ctx) ... end)
      local info = debug.getinfo(args[1], "Sl") or {}
      stage = {
        kind = kind,
        strat = "inline_lua",
        fn_ref = args[1],
        source = {
          file = info.source and info.source:gsub("^@", "") or "?",
          line = info.linedefined or 0,
          column = 1,
        },
      }
    elseif type(args[1]) == "string" and type(args[2]) == "string" then
      -- Positional form: ctx:transform("lua", "transforms/auth.lua")
      stage = {
        kind = kind,
        strat = args[1],
        path = args[2],
      }
    else
      error(table.concat({
        "pipeline stage declaration error",
        "",
        "route: " .. builder._route_id,
        "kind: " .. kind,
        "",
        "expected one of:",
        '  ctx:' .. kind .. '({ id = "...", strat = "lua", path = "..." })',
        '  ctx:' .. kind .. '("lua", "transforms/auth.lua")',
        '  ctx:' .. kind .. '(function(ctx) ... end)',
        "",
        "got: " .. type(args[1]) .. (args[2] and ", " .. type(args[2]) or ""),
      }, "\n"))
    end

    -- Validate kind
    if kind ~= "transform" and kind ~= "handle" and kind ~= "hook" then
      error("invalid stage kind: " .. tostring(kind) .. " (expected transform, handle, or hook)")
    end

    -- Validate strategy
    local strat = stage.strat
    if strat == "rust" then
      error(table.concat({
        "Rust stage strategy is not yet supported",
        "",
        "route: " .. builder._route_id,
        "stage: " .. tostring(stage.id or "<anonymous>"),
        "kind: " .. kind,
        "",
        "hint: use 'zig' for native stages, or 'lua' for Lua stages",
      }, "\n"))
    end
    if strat ~= "inline_lua" and strat ~= "lua" and strat ~= "zig" and strat ~= "rust" then
      error("invalid stage strategy: " .. tostring(strat) .. " (expected inline_lua, lua, zig, or rust)")
    end

    -- Set default may_short_circuit before phase-specific validation.
    if stage.may_short_circuit == nil then
      stage.may_short_circuit = (kind == "handle" or kind == "transform")
    end

    -- Validate hook phase and resource permissions.
    if kind == "hook" then
      if not stage.phase then
        error("hook stage requires a 'phase' field (pre_tree, post_match, pre_handler, post_handler, observe, error)")
      end
      if not contract.valid_phases[stage.phase] then
        error("invalid hook phase: " .. tostring(stage.phase) .. " (expected pre_tree, post_match, pre_handler, post_handler, observe, error)")
      end
      local hook_error = hooks.validate(stage)
      if hook_error then error(hook_error) end
    end

    return stage
  end

  --- Record a transform stage.
  --- Record a transform stage.
  ---@param ... any  Stage spec (table, function, or positional)
  ---@return PipelineBuilder
  function builder:transform(...)
    if not self._building then
      error("ctx:transform() called outside pipeline declaration — pipeline functions run at build time, not request time")
    end
    local stage = normalize_stage("transform", ...)
    self.stages[#self.stages + 1] = stage
    return self
  end

  --- Record a handle stage (primary response-producing stage).
  --- Record a handle stage (primary response-producing stage).
  ---@param ... any  Stage spec (table, function, or positional)
  ---@return PipelineBuilder
  function builder:handle(...)
    if not self._building then
      error("ctx:handle() called outside pipeline declaration — pipeline functions run at build time, not request time")
    end
    local stage = normalize_stage("handle", ...)
    self.stages[#self.stages + 1] = stage
    return self
  end

  --- Record a hook stage.
  --- Record a hook stage.
  ---@param phase string  Hook phase (pre_tree, post_match, etc.)
  ---@param stage_or_fn table|function  Stage spec or inline function
  ---@return PipelineBuilder
  function builder:hook(phase, stage_or_fn)
    if not self._building then
      error("ctx:hook() called outside pipeline declaration")
    end
    local stage
    if type(stage_or_fn) == "function" then
      local info = debug.getinfo(stage_or_fn, "Sl") or {}
      stage = {
        kind = "hook",
        phase = phase,
        strat = "inline_lua",
        fn_ref = stage_or_fn,
        source = {
          file = info.source and info.source:gsub("^@", "") or "?",
          line = info.linedefined or 0,
          column = 1,
        },
      }
    elseif type(stage_or_fn) == "table" then
      stage = stage_or_fn
      stage.kind = "hook"
      stage.phase = phase
    else
      error("ctx:hook() requires a table or function argument")
    end
    if not contract.valid_phases[phase] then
      error("invalid hook phase: " .. tostring(phase))
    end
    if stage.may_short_circuit == nil then stage.may_short_circuit = false end
    local hook_error = hooks.validate(stage)
    if hook_error then error(hook_error) end
    self.stages[#self.stages + 1] = stage
    return self
  end

  --- Alias for transform (some users prefer use/pipe naming).
  --- Alias for transform (some users prefer use/pipe naming).
  ---@param ... any  Stage spec
  ---@return PipelineBuilder
  function builder:use(...)
    return self:transform(...)
  end

  return builder
end

contract.PipelineBuilder = PipelineBuilder

-- ============================================================
-- Legacy handler lowering
-- ============================================================

--- Lower a legacy handler (string, function, or table) into a pipeline stage.
--- This is the "sugar" — internally, every handler is a pipeline stage.
--- Lower a legacy handler (string, function, or table) into a pipeline stage.
--- This is the "sugar" — internally, every handler is a pipeline stage.
---@param handler any  Legacy handler (string, function, or table)
---@return StageContract|nil, table|nil  Stage contract, or nil + special handler (file/dir)
local function lower_handler_to_stage(handler)
  local kind = type(handler)

  if kind == "string" then
    -- Zig symbol: "handlers.health"
    return {
      kind = "handle",
      strat = "zig",
      symbol = handler:match("([%w_]+)$") or handler,
      import = handler,
      source = source_info(5),
      _legacy = true,
    }
  end

  if kind == "function" then
    -- Inline Lua function
    local info = debug.getinfo(handler, "Sl") or {}
    return {
      kind = "handle",
      strat = "inline_lua",
      fn_ref = handler,
      source = {
        file = info.source and info.source:gsub("^@", "") or "?",
        line = info.linedefined or 0,
        column = 1,
      },
      _legacy = true,
    }
  end

  if kind == "table" then
    -- Table handler shapes from route.lua
    if handler.kind == "lua" then
      return {
        kind = "handle",
        strat = "lua",
        path = handler.path,
        module = handler.module,
        source = source_info(5),
        _legacy = true,
      }
    end
    if handler.kind == "zig" then
      return {
        kind = "handle",
        strat = "zig",
        symbol = handler.symbol:match("([%w_]+)$") or handler.symbol,
        import = handler.symbol,
        source = source_info(5),
        _legacy = true,
      }
    end
    if handler.kind == "zig_file" then
      return {
        kind = "handle",
        strat = "zig",
        path = handler.path,
        symbol = handler.path:gsub("%.zig$", ""):gsub("[/\\]+", "_"):gsub("%W", "_"),
        decl = handler.decl or "handle",
        source = source_info(5),
        _legacy = true,
      }
    end
    -- file/dir handlers are special — keep as-is in the handler field
    -- for the static file serving system
    return nil, handler
  end

  error("unsupported handler shape: " .. kind)
end

contract.lower_handler_to_stage = lower_handler_to_stage

-- ============================================================
-- Route declaration validation
-- ============================================================

--- Validate a route declaration and return its form.
---@param decl table  Route declaration
---@return string  "canonical" or "legacy"
local function validate_route_declaration(decl)
  if type(decl) ~= "table" then
    error("route declaration must be a table")
  end

  -- Check for canonical form
  if decl.route ~= nil then
    -- Canonical table form: { route = "/path", pipeline = function(ctx) ... end, ... }
    if type(decl.route) ~= "string" or decl.route == "" then
      error(table.concat({
        "Route declaration error",
        "",
        "missing or invalid required field: route",
        "",
        "expected:",
        '  app:get({',
        '    route = "/path",',
        '    pipeline = function(ctx) ... end',
        "  })",
      }, "\n"))
    end

    contract.reject_unsupported_body_features(decl, decl.route)

    -- Check conflicting handler and pipeline
    if decl.handler ~= nil and decl.pipeline ~= nil then
      error(table.concat({
        "Route declaration error",
        "",
        "conflicting fields: 'handler' and 'pipeline' are mutually exclusive",
        "",
        "route: " .. decl.route,
        "",
        "hint: use 'handler' as sugar for a single-stage pipeline,",
        "or use 'pipeline' for multi-stage routes. Not both.",
      }, "\n"))
    end

    -- Validate policy
    if decl.policy ~= nil and type(decl.policy) ~= "table" then
      error("route 'policy' must be a table, got " .. type(decl.policy))
    end

    -- Validate hooks
    if decl.hooks ~= nil and type(decl.hooks) ~= "table" then
      error("route 'hooks' must be a table, got " .. type(decl.hooks))
    end

    return "canonical"
  end

  contract.reject_unsupported_body_features(decl, decl[1] or decl.path)

  return "legacy"
end

contract.validate_route_declaration = validate_route_declaration

-- ============================================================
-- Build a RouteContract from a declaration
-- ============================================================

--- Build a complete RouteContract from any declaration form.
--- This is the single entry point that all route methods call.
--- Build a complete RouteContract from any declaration form.
--- This is the single entry point that all route methods call.
---@param method string  HTTP method (GET, POST, etc.)
---@param decl table  Declaration (canonical table or legacy positional)
---@param scope? table  Mount scope chain
---@return RouteContract
function contract.build(method, decl, scope)
  local source = validate_route_declaration(decl)
  local route_contract

  if source == "canonical" then
    -- Canonical table form
    route_contract = {
      method = method,
      route = decl.route,
      id = decl.id,
      name = decl.name,
      message = decl.message,
      message_source = decl.message_source,
      policy = decl.policy,
      hooks = decl.hooks,
      meta = decl.meta,
      params = decl.params or {},
      query = decl.query or {},
      body = decl.body,
      memory = decl.memory or {},
      capabilities = decl.capabilities or {},
      scope = scope,
      source = source_info(4),
      _source_form = "canonical",
    }

    -- Build pipeline
    if decl.pipeline ~= nil then
      local builder = PipelineBuilder(route_contract.id or (method .. " " .. decl.route))
      local fn = decl.pipeline
      local ok, err = pcall(fn, builder)
      if not ok then
        error(table.concat({
          "pipeline declaration failed",
          "",
          "route: " .. (route_contract.id or route_contract.route),
          "method: " .. method,
          "",
          "error:",
          "  " .. tostring(err),
        }, "\n"))
      end
      builder._building = false
      route_contract.pipeline = builder.stages
    elseif decl.handler ~= nil then
      -- Handler sugar in canonical form
      local stage, special = lower_handler_to_stage(decl.handler)
      if stage then
        route_contract.pipeline = { stage }
      elseif special then
        -- file/dir handler — keep as special handler
        route_contract.handler = special
        route_contract.pipeline = nil
      end
    end
  else
    -- Legacy positional form: app:get(path, opts?, handler)
    if not decl[1] and not decl.path then
      error(table.concat({
        "Route declaration error",
        "",
        "missing required field: route",
        "",
        "expected one of:",
        '  app:get({ route = "/path", pipeline = function(ctx) ... end })',
        '  app:get("/path", handler)',
      }, "\n"))
    end
    route_contract = {
      method = method,
      route = decl[1] or decl.path,
      params = decl.params or (type(decl[2]) == "table" and decl[2].params) or {},
      message = decl.message or (type(decl[2]) == "table" and decl[2].message),
      message_source = decl.message_source or (type(decl[2]) == "table" and decl[2].message_source),
      query = decl.query or (type(decl[2]) == "table" and decl[2].query) or {},
      body = decl.body or (type(decl[2]) == "table" and decl[2].body),
      memory = decl.memory or (type(decl[2]) == "table" and decl[2].memory) or {},
      capabilities = decl.capabilities or (type(decl[2]) == "table" and decl[2].capabilities) or {},
      scope = scope,
      source = source_info(4),
      _source_form = "legacy_signature",
    }

    -- In legacy form, args are: [1]=path, [2]=opts or handler, [3]=handler (if opts present)
    local handler = nil
    if type(decl[3]) == "function" or type(decl[3]) == "string" or (type(decl[3]) == "table" and decl[3].kind) then
      -- Three-arg form: path, opts, handler
      handler = decl[3]
    elseif type(decl[2]) == "function" or type(decl[2]) == "string" or (type(decl[2]) == "table" and decl[2].kind) then
      -- Two-arg form: path, handler (no opts)
      handler = decl[2]
    end

    if handler ~= nil then
      local stage, special = lower_handler_to_stage(handler)
      if stage then
        route_contract.pipeline = { stage }
      elseif special then
        route_contract.handler = special
        route_contract.pipeline = nil
      end
    end
  end

  contract.validate_pipeline(route_contract.pipeline, route_contract.id or route_contract.route, route_contract)

  return route_contract
end

function contract.validate_pipeline(pipeline, route_label, route_contract)
  if pipeline then
    local seen_ids = {}
    for _, stage in ipairs(pipeline) do
      if stage.id then
        if seen_ids[stage.id] then
          error(table.concat({
            "duplicate stage id in pipeline",
            "",
            "route: " .. tostring(route_label),
            "stage id: " .. stage.id,
            "",
            "hint: stage ids must be unique within a route pipeline",
          }, "\n"))
        end
        seen_ids[stage.id] = true
      end
    end

    -- Validate deterministic hook ordering around the response producer.
    local first_handle_position = nil
    for index, stage in ipairs(pipeline) do
      if stage.kind == "handle" and not first_handle_position then
        first_handle_position = index
      end
    end
    if first_handle_position then
      for index, stage in ipairs(pipeline) do
        if stage.kind == "hook" then
          if before_handle_phases[stage.phase] and index > first_handle_position then
            error(table.concat({
              "invalid hook ordering in pipeline",
              "",
              "route: " .. tostring(route_label),
              "hook phase: " .. tostring(stage.phase),
              "stage id: " .. tostring(stage.id or "<anonymous>"),
              "",
              "hint: pre_tree, post_match, and pre_handler hooks must appear before the handle stage",
            }, "\n"))
          end
          if after_handle_phases[stage.phase] and index < first_handle_position then
            error(table.concat({
              "invalid hook ordering in pipeline",
              "",
              "route: " .. tostring(route_label),
              "hook phase: " .. tostring(stage.phase),
              "stage id: " .. tostring(stage.id or "<anonymous>"),
              "",
              "hint: post_handler, observe, and error hooks must appear after the handle stage",
            }, "\n"))
          end
        end
      end
    end

    -- Validate that pipeline has at least one handle or response-producing stage
    local has_handler = false
    for _, stage in ipairs(pipeline) do
      if stage.kind == "handle" then
        has_handler = true
        break
      end
    end
    if not has_handler and #pipeline > 0 and route_contract then
      -- Transforms only — the last one is expected to produce a response
      -- This is valid but worth noting in diagnostics
      route_contract._transform_only_pipeline = true
    end
  end

end

-- ============================================================
-- Graph serialization for inspection/debug output
-- ============================================================

--- Serialize a RouteContract to a plain table for graph inspection.
--- Serialize a RouteContract to a plain table for graph inspection.
---@param route_contract RouteContract
---@return table  Inspectable table with pipeline stages, hooks, policy
function contract.serialize(route_contract)
  local out = {
    method = route_contract.method,
    route = route_contract.route,
    id = route_contract.id,
    name = route_contract.name,
    message = route_contract.message,
    source_form = route_contract._source_form,
    policy = route_contract.policy,
    has_pipeline = route_contract.pipeline ~= nil,
    pipeline = {},
    hooks = {},
  }

  if route_contract.pipeline then
    for _, stage in ipairs(route_contract.pipeline) do
      out.pipeline[#out.pipeline + 1] = {
        id = stage.id,
        kind = stage.kind,
        phase = stage.phase,
        strat = stage.strat,
        path = stage.path,
        symbol = stage.symbol,
        inline = stage.strat == "inline_lua",
        owner = stage.owner,
        may_short_circuit = stage.may_short_circuit,
        reads = stage.reads,
        writes = stage.writes,
        source = stage.source,
      }
    end
  end

  if route_contract.hooks then
    for _, hook in ipairs(route_contract.hooks) do
      out.hooks[#out.hooks + 1] = {
        phase = hook.phase or (hook.stage and hook.stage.phase),
        owner = hook.owner_plugin,
        stage_id = hook.stage and hook.stage.id,
      }
    end
  end

  return out
end

return contract
