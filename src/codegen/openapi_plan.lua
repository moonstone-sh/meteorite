--- OpenAPI planning metadata emitter.
--- Produces Meteorite-specific schema/route metadata before final OpenAPI JSON.

local helpers = require("codegen.helpers")
local schema_doc = require("codegen.schema_doc")

local openapi_plan = {}

local function has_fields(schema)
  local props = schema and schema.properties or {}
  for _, _ in pairs(props) do return true end
  return false
end

local function path_template(raw_path)
  return tostring(raw_path or ""):gsub(":([%a_][%w_]*)%*", "{%1}"):gsub(":([%a_][%w_]*)", "{%1}")
end

local function parameter_list(location, items)
  local parameters = {}
  for _, item in ipairs(schema_doc.items(items)) do
    parameters[#parameters + 1] = {
      name = item.name,
      in_ = location,
      required = location == "path" or item.optional ~= true,
      schema = schema_doc.json_schema(item),
    }
  end
  return parameters
end

local function append_all(target, source)
  for _, item in ipairs(source or {}) do target[#target + 1] = item end
end

local function security_schemes(route)
  local schemes = {}
  local validation = route.validation or {}
  for _, item in ipairs(validation.headers or {}) do
    local name = tostring(item.name or "")
    local lowered = name:lower()
    if lowered == "authorization" then schemes[#schemes + 1] = "authorization-header"
    elseif lowered:find("token", 1, true) or lowered:find("api%-key") then schemes[#schemes + 1] = name end
  end
  for _, item in ipairs(validation.cookies or {}) do schemes[#schemes + 1] = "cookie:" .. tostring(item.name) end
  if route.runtime and route.runtime.requires_auth then schemes[#schemes + 1] = "meteorite-auth-capability" end
  table.sort(schemes)
  return schemes
end

function openapi_plan.emit(graph)
  local routes = {}
  local messages = {}
  for _, route in ipairs(graph.routes or {}) do
    local validation = route.validation or {}
    local json_body = schema_doc.object_schema(validation.json_body)
    local form_body = schema_doc.object_schema(validation.form_body)
    local request_body = {}
    if has_fields(json_body) then request_body["application/json"] = json_body end
    if has_fields(form_body) then request_body["application/x-www-form-urlencoded"] = form_body end
    local parameters = {}
    append_all(parameters, parameter_list("path", route.params))
    append_all(parameters, parameter_list("query", route.query))
    append_all(parameters, parameter_list("header", validation.headers))
    append_all(parameters, parameter_list("cookie", validation.cookies))
    routes[#routes + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      http = route.http,
      message = route.message,
      method = helpers.method_enum(route.method),
      path = route.raw_path,
      template = path_template(route.raw_path),
      operationId = route.operation_id or route.id,
      summary = route.summary,
      description = route.description,
      tags = route.tags,
      parameters = parameters,
      requestBody = request_body,
      responses = schema_doc.response_count(route.responses) > 0 and schema_doc.response_schemas(route.responses) or {
        default = {
          description = "Meteorite route response schema not declared",
          missing_schema = true,
        },
      },
      security = security_schemes(route),
    }
  end
  for _, route in ipairs(graph.messages or {}) do
    local validation = route.validation or {}
    messages[#messages + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      message = route.message,
      metadata = schema_doc.object_schema(route.params),
      json_body = schema_doc.object_schema(validation.json_body),
      form_body = schema_doc.object_schema(validation.form_body),
      responses = schema_doc.response_count(route.responses) > 0 and schema_doc.response_schemas(route.responses) or {
        default = { description = "Meteorite message response schema not declared", missing_schema = true },
      },
    }
  end
  return {
    format = "meteorite.openapi-plan.v0",
    openapi = "3.1.0",
    routes = routes,
    messages = messages,
  }
end

return openapi_plan
