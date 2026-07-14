--- OpenAPI 3.1 JSON spec emitter.
--- Transforms the normalized Meteorite graph into a complete OpenAPI 3.1 document.
---
--- @class OpenApiModule
--- @field emit fun(graph: table, opts?: table): table  Build OpenAPI 3.1 document from graph
--- @field emit_json fun(graph: table, opts?: table): string  Build and serialize OpenAPI 3.1 JSON

local json = require("utils.json")
local report = require("codegen.report")
local schema_doc = require("codegen.schema_doc")

local openapi = {}

--- Convert a Meteorite raw path to an OpenAPI path template.
--- /users/:id → /users/{id}
--- /static/* → /static/{wildcard}
--- /files/:path* → /files/{path}
local function path_template(raw_path)
  return tostring(raw_path or "")
    :gsub(":([%a_][%w_]*)%*", "{%1}")
    :gsub(":([%a_][%w_]*)", "{%1}")
    :gsub("%*$", "{wildcard}")
end

--- Map Meteorite methods to OpenAPI operation keys.
local method_map = {
  GET = "get",
  HEAD = "head",
  POST = "post",
  PUT = "put",
  PATCH = "patch",
  DELETE = "delete",
  OPTIONS = "options",
}

--- Build OpenAPI security scheme objects from route security metadata.
local function build_security_schemes(routes)
  local schemes = {}
  local seen = {}
  for _, route in ipairs(routes or {}) do
    -- Extract security info from validation headers
    local validation = route.validation or {}
    for _, item in ipairs(validation.headers or {}) do
      local name = tostring(item.name or ""):lower()
      if name == "authorization" then
        if not seen["bearerAuth"] then
          seen["bearerAuth"] = true
          schemes["bearerAuth"] = { type = "http", scheme = "bearer" }
        end
      end
    end
    for _, item in ipairs(validation.cookies or {}) do
      local name = tostring(item.name or "")
      if name ~= "" and not seen["cookie_" .. name] then
        seen["cookie_" .. name] = true
        schemes["cookie_" .. name] = { type = "apiKey", ["in"] = "cookie", name = name }
      end
    end
  end
  return schemes
end

--- Build a response object for an OpenAPI operation.
local function build_responses(route)
  local responses = {}
  local count = 0
  for status, spec in pairs(route.responses or {}) do
    local key = tostring(status)
    local response = { description = "" }
    if type(spec) == "table" then
      if spec.description then response.description = spec.description end
      if spec.schema then
        response.content = { ["application/json"] = { schema = spec.schema } }
      elseif spec.json then
        response.content = { ["application/json"] = { schema = schema_doc.object_schema(spec.json) } }
      end
    end
    if response.description == "" then response.description = "Response for status " .. key end
    responses[key] = response
    count = count + 1
  end
  if count == 0 then
    responses["default"] = { description = "Meteorite route response schema not declared" }
  end
  return responses
end

--- Build parameter list for an OpenAPI operation.
local function build_parameters(route)
  local params = {}
  local validation = route.validation or {}

  -- Path parameters
  for _, item in ipairs(route.params or {}) do
    params[#params + 1] = {
      name = item.name,
      ["in"] = "path",
      required = true,
      schema = schema_doc.json_schema(item),
    }
  end

  -- Query parameters
  for _, item in ipairs(route.query or {}) do
    params[#params + 1] = {
      name = item.name,
      ["in"] = "query",
      required = item.optional ~= true,
      schema = schema_doc.json_schema(item),
    }
  end

  -- Header parameters
  for _, item in ipairs(validation.headers or {}) do
    params[#params + 1] = {
      name = item.name,
      ["in"] = "header",
      required = item.optional ~= true,
      schema = schema_doc.json_schema(item),
    }
  end

  -- Cookie parameters
  for _, item in ipairs(validation.cookies or {}) do
    params[#params + 1] = {
      name = item.name,
      ["in"] = "cookie",
      required = item.optional ~= true,
      schema = schema_doc.json_schema(item),
    }
  end

  return params
end

--- Build request body for an OpenAPI operation.
local function build_request_body(route)
  local validation = route.validation or {}
  local content = {}

  local json_items = validation.json_body or {}
  if schema_doc.has_items(json_items) then
    content["application/json"] = { schema = schema_doc.object_schema(json_items) }
  end

  local form_items = validation.form_body or {}
  if schema_doc.has_items(form_items) then
    content["application/x-www-form-urlencoded"] = { schema = schema_doc.object_schema(form_items) }
  end

  if next(content) then
    return { required = false, content = content }
  end
  return nil
end

--- Build security requirements for an operation.
local function build_security(route)
  local security = {}
  local validation = route.validation or {}
  for _, item in ipairs(validation.headers or {}) do
    if tostring(item.name or ""):lower() == "authorization" then
      security[#security + 1] = { ["bearerAuth"] = {} }
    end
  end
  for _, item in ipairs(validation.cookies or {}) do
    security[#security + 1] = { ["cookie_" .. tostring(item.name)] = {} }
  end
  if #security == 0 then return nil end
  return security
end

--- Build the complete OpenAPI 3.1 document.
---@param graph table  Normalized Meteorite graph
---@param opts? table  Options (title, version, description)
---@return table  OpenAPI 3.1 document
function openapi.emit(graph, opts)
  opts = opts or {}
  local app_name = (graph.app and graph.app.name) or "meteorite-app"
  local doc = {
    openapi = "3.1.0",
    info = {
      title = opts.title or app_name,
      version = opts.version or "0.1.0",
    },
    paths = {},
  }
  if opts.description then doc.info.description = opts.description end

  -- Build paths
  for _, route in ipairs(graph.routes or {}) do
    local template = path_template(route.raw_path)
    if not doc.paths[template] then doc.paths[template] = {} end
    local path_item = doc.paths[template]

    local methods_to_emit = {}
    if route.method == "ALL" then
      methods_to_emit = { "get", "post", "put", "patch", "delete", "head", "options" }
    else
      local op_key = method_map[route.method]
      if op_key then methods_to_emit = { op_key } end
    end

    for _, op_key in ipairs(methods_to_emit) do
      if not path_item[op_key] then
        local operation = {
          operationId = route.operation_id or (route.id .. (route.method == "ALL" and ("_" .. op_key) or "")),
          parameters = build_parameters(route),
          responses = build_responses(route),
        }
        if route.summary then operation.summary = route.summary end
        if route.description then operation.description = route.description end
        if route.tags then
          operation.tags = route.tags
        elseif route.scope and route.scope.id and route.scope.id ~= "root" then
          operation.tags = { route.scope.id }
        end
        local request_body = build_request_body(route)
        if request_body then operation.requestBody = request_body end
        local security = build_security(route)
        if security then operation.security = security end

        -- Add tags from scope
        if route.scope and route.scope.id and route.scope.id ~= "root" then
          operation.tags = { route.scope.id }
        end

        path_item[op_key] = operation
      end
    end
  end

  -- Build components/securitySchemes
  local security_schemes = build_security_schemes(graph.routes or {})
  if next(security_schemes) then
    doc.components = { securitySchemes = security_schemes }
  end

  -- Sort paths alphabetically
  local sorted_paths = {}
  for path, item in pairs(doc.paths) do
    sorted_paths[#sorted_paths + 1] = path
  end
  table.sort(sorted_paths)
  local ordered_paths = {}
  for _, path in ipairs(sorted_paths) do
    ordered_paths[path] = doc.paths[path]
  end
  doc.paths = ordered_paths

  return doc
end

--- Build and serialize the OpenAPI 3.1 document as JSON.
---@param graph table  Normalized Meteorite graph
---@param opts? table  Options (title, version, description, pretty)
---@return string  OpenAPI 3.1 JSON text
function openapi.emit_json(graph, opts)
  opts = opts or {}
  local doc = openapi.emit(graph, opts)
  if opts.pretty then
    return json.pretty_encode(doc)
  end
  return json.encode(doc)
end

return openapi
