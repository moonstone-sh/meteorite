--- Schema IR emitter for generated route/message metadata.

local helpers = require("codegen.helpers")
local schema_doc = require("codegen.schema_doc")

local schema_ir = {}

function schema_ir.emit(graph)
  local routes = {}
  local messages = {}
  for _, route in ipairs(graph.routes or {}) do
    local validation = route.validation or {}
    routes[#routes + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      http = route.http,
      message = route.message,
      method = helpers.method_enum(route.method),
      path = route.raw_path,
      params = schema_doc.object_schema(route.params),
      query = schema_doc.object_schema(route.query),
      headers = schema_doc.object_schema(validation.headers),
      cookies = schema_doc.object_schema(validation.cookies),
      json_body = schema_doc.object_schema(validation.json_body),
      form_body = schema_doc.object_schema(validation.form_body),
      responses = schema_doc.response_schemas(route.responses),
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
      responses = schema_doc.response_schemas(route.responses),
    }
  end
  return {
    format = "meteorite.schema-ir.v0",
    routes = routes,
    messages = messages,
  }
end

return schema_ir
