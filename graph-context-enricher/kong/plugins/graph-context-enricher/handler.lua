local cjson = require "cjson.safe"
local http = require "resty.http"

local kong = kong

local plugin = {
  PRIORITY = 2100,
  VERSION = "1.0.0",
}

local compiled_cache = setmetatable({}, { __mode = "k" })

local function normalize_header_name(value)
  return value and value:lower() or nil
end

local function log_event(level, code, message, extra)
  local payload = {
    plugin = "graph-context-enricher",
    code = code,
    message = message,
  }

  if extra then
    for key, value in pairs(extra) do
      payload[key] = value
    end
  end

  if level == "warn" then
    kong.log.warn(cjson.encode(payload))
  else
    kong.log.err(cjson.encode(payload))
  end
end

local function compile_config(conf)
  local compiled = compiled_cache[conf]
  if compiled then
    return compiled
  end

  compiled = {
    output_mappings = {},
    cleared_headers = {},
    static_request_headers = {},
    forward_headers = {},
  }

  for _, mapping in ipairs(conf.output_header_mappings) do
    local normalized = {
      header = normalize_header_name(mapping.header),
      source_path = mapping.source_path,
      json_encode = mapping.json_encode == true,
    }

    compiled.output_mappings[#compiled.output_mappings + 1] = normalized
    compiled.cleared_headers[#compiled.cleared_headers + 1] = normalized.header
  end

  for _, item in ipairs(conf.static_request_headers) do
    compiled.static_request_headers[#compiled.static_request_headers + 1] = {
      header = normalize_header_name(item.header),
      value = item.value,
    }
  end

  for _, header in ipairs(conf.forward_headers) do
    compiled.forward_headers[#compiled.forward_headers + 1] = normalize_header_name(header)
  end

  compiled_cache[conf] = compiled
  return compiled
end

local function clear_headers(compiled)
  for _, header in ipairs(compiled.cleared_headers) do
    kong.service.request.clear_header(header)
  end
end

local function split_path(path)
  local parts = {}

  for part in path:gmatch("[^.]+") do
    if part ~= "$" then
      parts[#parts + 1] = part
    end
  end

  return parts
end

local function read_path(source, path)
  local current = source

  for _, part in ipairs(split_path(path)) do
    if type(current) ~= "table" then
      return nil
    end

    current = current[part]
  end

  return current
end

local function set_path(target, path, value)
  local current = target
  local parts = split_path(path)

  for index = 1, #parts - 1 do
    local part = parts[index]
    if type(current[part]) ~= "table" then
      current[part] = {}
    end
    current = current[part]
  end

  current[parts[#parts]] = value
end

local function write_header(header, value, json_encode)
  if value == nil or value == cjson.null then
    kong.service.request.clear_header(header)
    return
  end

  if type(value) == "table" then
    kong.service.request.set_header(header, json_encode and cjson.encode(value) or table.concat(value, ","))
    return
  end

  kong.service.request.set_header(header, tostring(value))
end

local function build_variables(conf)
  local variables = {}

  for _, mapping in ipairs(conf.variable_mappings) do
    local value = kong.request.get_header(mapping.from_header)

    if (not value or value == "") and mapping.required then
      return nil, mapping.from_header
    end

    variables[mapping.variable] = value
  end

  return variables
end

local function build_request_headers(compiled)
  local headers = {
    ["Content-Type"] = "application/json",
  }

  for _, item in ipairs(compiled.static_request_headers) do
    headers[item.header] = item.value
  end

  for _, header in ipairs(compiled.forward_headers) do
    local value = kong.request.get_header(header)
    if value and value ~= "" then
      headers[header] = value
    end
  end

  return headers
end

local function make_request(conf, compiled, body)
  local attempts = conf.retries + 1
  local last_err

  for _ = 1, attempts do
    local client = http.new()
    client:set_timeouts(conf.connect_timeout_ms, conf.send_timeout_ms, conf.read_timeout_ms)

    local response, err = client:request_uri(conf.graph_url, {
      method = "POST",
      ssl_verify = conf.ssl_verify,
      body = cjson.encode(body),
      headers = build_request_headers(compiled),
    })

    if response and response.status == 200 then
      return response
    end

    last_err = err or ("http_status:" .. tostring(response and response.status))
  end

  return nil, last_err
end

local function reject(code, status, message)
  return kong.response.exit(status, {
    message = message,
    code = code,
  })
end

local function resolve_error_response(conf, key, fallback_code, fallback_message)
  local responses = conf.error_responses or {}
  local response = responses[key] or {}

  return response.client_code or fallback_code, response.message or fallback_message
end

local function maybe_handle_result_policy(conf, code, status, message, extra)
  local client_code, client_message

  if (code == "GRAPH_REQUEST_FAILED" and conf.on_upstream_error == "pass")
     or (code == "MISSING_DATA" and conf.on_missing_data == "pass")
     or (code == "MULTIPLE_RESULTS" and conf.on_multiple_results == "pass") then
    log_event("warn", code, message, extra)
    return
  end

  if code == "GRAPH_REQUEST_FAILED" then
    client_code, client_message = resolve_error_response(conf, "graph_request_failed", code, message)
  elseif code == "MISSING_DATA" then
    client_code, client_message = resolve_error_response(conf, "missing_data", code, message)
  elseif code == "MULTIPLE_RESULTS" then
    client_code, client_message = resolve_error_response(conf, "multiple_results", code, message)
  else
    client_code, client_message = code, message
  end

  log_event("err", code, message, extra)
  return reject(client_code, status, client_message)
end

local function unwrap_arrays(conf, payload)
  for _, path in ipairs(conf.array_unwrap_paths) do
    local value = read_path(payload, path)

    if value ~= nil and value ~= cjson.null and type(value) == "table" then
      if value[1] == nil then
        return maybe_handle_result_policy(conf, "MISSING_DATA", 401, "Required graph data is missing", {
          path = path,
        }), true
      end

      if value[2] ~= nil then
        if conf.on_multiple_results == "first" then
          set_path(payload, path, value[1])
        else
          return maybe_handle_result_policy(conf, "MULTIPLE_RESULTS", 409, "Graph lookup returned multiple results", {
            path = path,
          }), true
        end
      else
        set_path(payload, path, value[1])
      end
    end
  end

  return nil, false
end

local function validate_required_paths(conf, payload)
  for _, path in ipairs(conf.required_paths) do
    local value = read_path(payload, path)
    if value == nil or value == cjson.null then
      return maybe_handle_result_policy(conf, "MISSING_DATA", 401, "Required graph data is missing", {
        path = path,
      }), true
    end
  end

  return nil, false
end

function plugin:access(conf)
  local compiled = compile_config(conf)
  clear_headers(compiled)

  local variables, missing_header = build_variables(conf)
  if not variables then
    local client_code, client_message = resolve_error_response(
      conf,
      "missing_required_input",
      "MISSING_REQUIRED_INPUT",
      "Required input header is missing"
    )
    return reject(client_code, 400, client_message .. ": " .. missing_header)
  end

  local response, err = make_request(conf, compiled, {
    query = conf.graph_query,
    variables = variables,
  })

  if not response then
    return maybe_handle_result_policy(conf, "GRAPH_REQUEST_FAILED", 502, "Graph lookup failed", {
      reason = err,
    })
  end

  local payload = cjson.decode(response.body or "")
  if not payload or payload.errors then
    local client_code, client_message = resolve_error_response(
      conf,
      "graph_error_response",
      "GRAPH_REQUEST_FAILED",
      "Graph lookup returned an error"
    )
    log_event("err", "GRAPH_REQUEST_FAILED", "Graph lookup returned an error", {
      graph_errors = payload and payload.errors or response.body,
    })
    return reject(client_code, 502, client_message)
  end

  if payload.data == nil or payload.data == cjson.null then
    return maybe_handle_result_policy(conf, "MISSING_DATA", 401, "Required graph data is missing", {
      path = "$.data",
    })
  end

  local exit_response, handled = unwrap_arrays(conf, payload)
  if handled then
    return exit_response
  end

  exit_response, handled = validate_required_paths(conf, payload)
  if handled then
    return exit_response
  end

  for _, mapping in ipairs(compiled.output_mappings) do
    local value = read_path(payload, mapping.source_path)
    if value == nil or value == cjson.null then
      exit_response, handled = maybe_handle_result_policy(conf, "MISSING_DATA", 401, "Required graph data is missing", {
        path = mapping.source_path,
      }), true

      if handled then
        return exit_response
      end
    end

    write_header(mapping.header, value, mapping.json_encode)
  end
end

return plugin
