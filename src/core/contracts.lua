--- Meteorite consumer for versioned, generated contract bundles.
---
--- Meteorite consumes the JSON artifact, never a Valua source module. That
--- keeps the service compiler independent of Valua's runtime and makes the
--- artifact used by Bun, Hydronium, and the server inspectable and portable.
local contracts = {}

local function index_document(document)
  if type(document) ~= "table" or document.format ~= "moonstone.contract-bundle.v1" then
    error("Meteorite contracts require a moonstone.contract-bundle.v1 document", 3)
  end
  local indexed = { document = document, exports = {} }
  for _, item in ipairs(document.exports or {}) do
    if type(item) ~= "table" or type(item.id) ~= "string" or type(item.input) ~= "table" or type(item.output) ~= "table" then
      error("Meteorite contract bundle has an invalid export entry", 3)
    end
    if indexed.exports[item.id] then error("Meteorite contract bundle has duplicate export `" .. item.id .. "`", 3) end
    indexed.exports[item.id] = item
  end

  function indexed:input(id)
    local item = self.exports[id]
    if not item then error("Meteorite contract export not found: " .. tostring(id), 2) end
    return { _meteorite_contract_input = true, id = id, schema = item.input }
  end

  function indexed:response(id, opts)
    local item = self.exports[id]
    if not item then error("Meteorite contract export not found: " .. tostring(id), 2) end
    opts = opts or {}
    local response = {}
    for key, value in pairs(opts) do response[key] = value end
    response.contract_id = id
    response.schema = item.output
    return response
  end

  return indexed
end

--- Construct a consumer from an already parsed generated document. This is the
--- preferred API in tests and build integrations that own JSON parsing.
function contracts.from_document(document)
  return index_document(document)
end

--- Load one generated contract bundle from disk at graph-build time.
function contracts.load(path)
  local file, open_err = io.open(path, "rb")
  if not file then error("cannot read Meteorite contract bundle `" .. tostring(path) .. "`: " .. tostring(open_err), 2) end
  local text = file:read("*a")
  file:close()
  local ok, cjson = pcall(require, "cjson.safe")
  if not ok then cjson = require("cjson") end
  local document, decode_err = cjson.decode(text)
  if not document then error("cannot decode Meteorite contract bundle `" .. tostring(path) .. "`: " .. tostring(decode_err), 2) end
  return index_document(document)
end

--- Lower the currently compilable input subset to Meteorite's existing flat
--- JSON-body validators. This is deliberately not a partial JSON Schema
--- interpreter: unsupported structure is an error, never ignored.
function contracts.lower_input(reference)
  if type(reference) ~= "table" or type(reference.id) ~= "string" or type(reference.schema) ~= "table" then
    error("Meteorite contract input must come from bundle:input(id)", 2)
  end
  local schema = reference.schema
  if schema.type ~= "object" or type(schema.properties) ~= "table" then
    error("Meteorite contract input `" .. reference.id .. "` must be a JSON object", 2)
  end
  if schema.additionalProperties ~= false then
    error("Meteorite contract input `" .. reference.id .. "` must forbid additional properties", 2)
  end
  local required = {}
  for _, name in ipairs(schema.required or {}) do required[name] = true end
  local fields = {}
  for name, property in pairs(schema.properties) do
    if type(property) ~= "table" then error("Meteorite contract input `" .. reference.id .. "` has invalid property `" .. tostring(name) .. "`", 2) end
    local value_type = property.type
    local kind
    if value_type == "string" then kind = "string"
    elseif value_type == "integer" then kind = "i32"
    elseif value_type == "boolean" then kind = "bool"
    else
      error("Meteorite cannot compile contract input `" .. reference.id .. "` property `" .. tostring(name) .. "` of type " .. tostring(value_type) .. "; supported: string, integer, boolean", 2)
    end
    if property.pattern or property.anyOf or property["$ref"] or property.items or property.properties then
      error("Meteorite cannot compile structured contract input `" .. reference.id .. "` property `" .. tostring(name) .. "` yet", 2)
    end
    fields[name] = {
      type = kind,
      optional = not required[name],
      min = property.minimum,
      max = property.maximum,
      min_len = property.minLength,
      max_len = property.maxLength,
    }
  end
  return fields
end

return contracts
