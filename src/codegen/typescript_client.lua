--- Deterministic, dependency-free browser TypeScript client emitter.
---
--- This deliberately consumes Meteorite's normalized route graph rather than
--- reparsing OpenAPI JSON. OpenAPI remains a public artifact; the client gets
--- the same route and contract schemas before serialization can lose identity.
local typescript_client = {}

local function sorted_routes(graph)
  local routes = {}
  for _, route in ipairs((graph and graph.routes) or {}) do routes[#routes + 1] = route end
  table.sort(routes, function(a, b)
    local left = table.concat({ tostring(a.method or ""), tostring(a.raw_path or a.path or ""), tostring(a.id or "") }, " ")
    local right = table.concat({ tostring(b.method or ""), tostring(b.raw_path or b.path or ""), tostring(b.id or "") }, " ")
    return left < right
  end)
  return routes
end

local function identifier(value)
  value = tostring(value or ""):gsub("[^%w_]", "_"):gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if value == "" then value = "route" end
  if value:match("^%d") then value = "route_" .. value end
  return value
end

local function pascal(value)
  local out = ""
  for part in identifier(value):gmatch("[^_]+") do out = out .. part:sub(1, 1):upper() .. part:sub(2) end
  return out == "" and "Route" or out
end

local function route_name(route, seen)
  local meta = route.meta or route.openapi or {}
  local base = route.operation_id or route.operationId or meta.operationId
    or (tostring(route.method or "get"):lower() .. "_" .. tostring(route.raw_path or route.path or "route"))
  local name, number = identifier(base), 2
  local first = name
  while seen[name] do name = first .. "_" .. tostring(number); number = number + 1 end
  seen[name] = true
  return name
end

local function quote(value) return string.format("%q", tostring(value or "")) end

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function is_identifier(value)
  return type(value) == "string" and value:match("^[A-Za-z_$][A-Za-z0-9_$]*$") ~= nil
end

local function property_name(value)
  return is_identifier(value) and value or quote(value)
end

local function literal(value)
  if type(value) == "string" then return quote(value) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if value == nil then return "null" end
  return "unknown"
end

local function schema_type(schema, root, resolving)
  if type(schema) ~= "table" then return "unknown" end
  root = root or schema
  resolving = resolving or {}
  if type(schema["$ref"]) == "string" then
    local key = schema["$ref"]:match("^#/%$defs/(.+)$")
    if key and root["$defs"] and root["$defs"][key] then
      if resolving[key] then return "unknown" end
      resolving[key] = true
      local value = schema_type(root["$defs"][key], root, resolving)
      resolving[key] = nil
      return value
    end
    return "unknown"
  end
  if type(schema.enum) == "table" then
    local values = {}
    for _, value in ipairs(schema.enum) do values[#values + 1] = literal(value) end
    table.sort(values)
    return #values > 0 and table.concat(values, " | ") or "never"
  end
  if type(schema.anyOf) == "table" then
    local values = {}
    for _, value in ipairs(schema.anyOf) do values[#values + 1] = schema_type(value, root, resolving) end
    table.sort(values)
    return #values > 0 and table.concat(values, " | ") or "unknown"
  end
  if schema.type == "string" then return "string" end
  if schema.type == "integer" or schema.type == "number" then return "number" end
  if schema.type == "boolean" then return "boolean" end
  if schema.type == "null" then return "null" end
  if schema.type == "array" then return "Array<" .. schema_type(schema.items, root, resolving) .. ">" end
  if schema.type == "object" or schema.properties then
    local required, parts = {}, {}
    for _, name in ipairs(schema.required or {}) do required[name] = true end
    for _, name in ipairs(sorted_keys(schema.properties)) do
      parts[#parts + 1] = property_name(name) .. (required[name] and ": " or "?: ") .. schema_type(schema.properties[name], root, resolving) .. ";"
    end
    if schema.additionalProperties ~= false then parts[#parts + 1] = "[key: string]: unknown;" end
    return "{ " .. table.concat(parts, " ") .. " }"
  end
  return "unknown"
end

local function response_schema(route)
  local statuses = sorted_keys(route.responses)
  for _, status in ipairs(statuses) do
    if tostring(status):match("^2") then
      local response = route.responses[status]
      if type(response) == "table" then return response.schema or response.json or response.body end
    end
  end
  return nil
end

local function route_params(path)
  local params, seen = {}, {}
  for name in tostring(path or ""):gmatch(":([%a_][%w_]*)") do
    if not seen[name] then params[#params + 1] = name; seen[name] = true end
  end
  table.sort(params)
  return params
end

local function args_type(route, request_type)
  local fields = {}
  local params = route_params(route.raw_path or route.path)
  if #params > 0 then
    local parts = {}
    for _, name in ipairs(params) do parts[#parts + 1] = property_name(name) .. ": string | number;" end
    fields[#fields + 1] = "params: { " .. table.concat(parts, " ") .. " };"
  else
    fields[#fields + 1] = "params?: Record<string, string | number>;"
  end
  -- Keep the call shape uniform: generated implementations always pass
  -- args.query to appendQuery, including routes that currently declare none.
  -- It also makes adding an optional query parameter non-breaking for callers.
  fields[#fields + 1] = "query?: Record<string, string | number | boolean | null | undefined>;"
  if request_type then fields[#fields + 1] = "body: " .. request_type .. ";" end
  fields[#fields + 1] = "headers?: HeadersInit;"
  fields[#fields + 1] = "signal?: AbortSignal;"
  return "{ " .. table.concat(fields, " ") .. " }"
end

local function requires_args(route)
  return (route.json_contract and route.json_contract.schema) ~= nil or #route_params(route.raw_path or route.path) > 0
end

function typescript_client.emit(graph, opts)
  opts = opts or {}
  local entries, seen = {}, {}
  for _, route in ipairs(sorted_routes(graph)) do
    entries[#entries + 1] = { route = route, name = route_name(route, seen) }
  end

  local lines = {
    "/* Generated by Meteorite. Do not edit by hand. */",
    "",
    "export type MeteoriteFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;",
    "",
    "export interface MeteoriteClientOptions {",
    "  baseUrl?: string;",
    "  fetch?: MeteoriteFetch;",
    "  headers?: HeadersInit;",
    "}",
    "",
    "export class MeteoriteClientError extends Error {",
    "  constructor(readonly response: Response, readonly body: string) {",
    "    super(`Meteorite request failed: ${response.status} ${response.statusText}`);",
    "    this.name = \"MeteoriteClientError\";",
    "  }",
    "}",
    "",
  }

  for _, entry in ipairs(entries) do
    local base = pascal(entry.name)
    local request = entry.route.json_contract and entry.route.json_contract.schema or nil
    local response = response_schema(entry.route)
    if request then
      lines[#lines + 1] = "export type " .. base .. "Request = " .. schema_type(request) .. ";"
    end
    lines[#lines + 1] = "export type " .. base .. "Response = " .. schema_type(response) .. ";"
    lines[#lines + 1] = "export type " .. base .. "Args = " .. args_type(entry.route, request and base .. "Request" or nil) .. ";"
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "function appendQuery(path: string, query?: Record<string, string | number | boolean | null | undefined>): string {"
  lines[#lines + 1] = "  if (!query) return path;"
  lines[#lines + 1] = "  const parts = Object.keys(query).sort().flatMap((key) => { const value = query[key]; return value == null ? [] : [`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`]; });"
  lines[#lines + 1] = "  return parts.length === 0 ? path : `${path}?${parts.join(\"&\")}`;"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "function applyPath(template: string, params: Record<string, string | number> = {}): string {"
  lines[#lines + 1] = "  return template.replace(/:([A-Za-z_][A-Za-z0-9_]*)\\*?/g, (_match, name: string) => { const value = params[name]; if (value === undefined) throw new Error(`Meteorite client missing path param: ${name}`); return encodeURIComponent(String(value)); });"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "export function createClient(options: MeteoriteClientOptions = {}) {"
  lines[#lines + 1] = "  const request = options.fetch ?? globalThis.fetch;"
  lines[#lines + 1] = "  if (!request) throw new Error(\"Meteorite client requires fetch\");"
  lines[#lines + 1] = "  const baseUrl = (options.baseUrl ?? \"\").replace(/\\/$/, \"\");"
  lines[#lines + 1] = "  return {"
  for _, entry in ipairs(entries) do
    local route, base = entry.route, pascal(entry.name)
    local request = route.json_contract and route.json_contract.schema or nil
    local argument = "args: " .. base .. "Args"
    if not requires_args(route) then argument = argument .. " = {}" end
    lines[#lines + 1] = "    async " .. entry.name .. "(" .. argument .. "): Promise<" .. base .. "Response> {"
    lines[#lines + 1] = "      const path = appendQuery(applyPath(" .. quote(route.raw_path or route.path) .. ", args.params), args.query);"
    lines[#lines + 1] = "      const response = await request(baseUrl + path, { method: " .. quote(route.method) .. ", headers: { ...(options.headers ?? {}), ...(args.headers ?? {}), " .. (request and "\"content-type\": \"application/json\"," or "") .. " }, body: " .. (request and "JSON.stringify(args.body)" or "undefined") .. ", signal: args.signal });"
    lines[#lines + 1] = "      const text = await response.text();"
    lines[#lines + 1] = "      if (!response.ok) throw new MeteoriteClientError(response, text);"
    lines[#lines + 1] = "      return (text === \"\" ? undefined : JSON.parse(text)) as " .. base .. "Response;"
    lines[#lines + 1] = "    },"
  end
  lines[#lines + 1] = "  };"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

return typescript_client
