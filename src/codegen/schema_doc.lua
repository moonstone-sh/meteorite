--- Shared schema documentation helpers for OpenAPI JSON and planning outputs.

local helpers = require("codegen.helpers")

local schema_doc = {}

function schema_doc.items(fields)
  if not fields then return {} end
  if #fields > 0 then return fields end
  local items = {}
  for _, name in ipairs(helpers.sorted_keys(fields)) do
    local item = fields[name]
    if type(item) == "table" then
      local copy = {}
      for key, value in pairs(item) do copy[key] = value end
      copy.name = copy.name or name
      items[#items + 1] = copy
    end
  end
  return items
end

function schema_doc.has_items(fields)
  return #schema_doc.items(fields) > 0
end

function schema_doc.json_schema(item)
  local kind = item.type or item.kind or "string"
  local schema = { type = "string" }
  if kind == "u64" or kind == "i32" then
    schema.type = "integer"
    if kind == "u64" then schema.minimum = 0 end
  elseif kind == "bool" then
    schema.type = "boolean"
  elseif kind == "uuid" then
    schema.format = "uuid"
  elseif kind == "email" then
    schema.format = "email"
  elseif kind == "hex" then
    schema.pattern = "^[0-9A-Fa-f]+$"
  elseif kind == "slug" then
    schema.pattern = "^[A-Za-z0-9_-]+$"
  elseif kind == "token" then
    schema.pattern = "^[A-Za-z0-9._~-]+$"
  elseif kind == "pattern" then
    schema["x-meteorite-pattern-id"] = item.pattern_id or item.id
  end
  if item.max_len then schema.maxLength = item.max_len end
  if item.exact_len then
    schema.minLength = item.exact_len
    schema.maxLength = item.exact_len
  end
  if item.min then schema.minimum = item.min end
  if item.max then schema.maximum = item.max end
  return schema
end

function schema_doc.object_schema(fields)
  local properties = {}
  local required = {}
  for _, item in ipairs(schema_doc.items(fields)) do
    properties[item.name] = schema_doc.json_schema(item)
    if item.optional ~= true then required[#required + 1] = item.name end
  end
  table.sort(required)
  local schema = { type = "object", properties = properties, additionalProperties = false }
  if #required > 0 then schema.required = required end
  return schema
end

function schema_doc.response_schemas(responses)
  local out = {}
  for status, spec in pairs(responses or {}) do
    local key = tostring(status)
    if type(spec) == "table" then
      if spec.schema then out[key] = spec.schema
      elseif spec.json then out[key] = schema_doc.object_schema(spec.json)
      elseif spec.body then out[key] = schema_doc.object_schema(spec.body)
      else out[key] = spec end
    end
  end
  return out
end

function schema_doc.response_count(responses)
  local count = 0
  for _, _ in pairs(responses or {}) do count = count + 1 end
  return count
end

return schema_doc
