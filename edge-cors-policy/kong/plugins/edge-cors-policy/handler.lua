local kong = kong

local plugin = {
  PRIORITY = 3100,
  VERSION = "1.0.0",
}

local compiled_config_cache = setmetatable({}, { __mode = "k" })
local VARY_ORIGIN = { "Origin" }
local VARY_PREFLIGHT = {
  "Origin",
  "Access-Control-Request-Method",
  "Access-Control-Request-Headers",
  "Access-Control-Request-Private-Network",
}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_lower(value)
  return value and value:lower() or nil
end

local function split_authority(authority)
  if not authority or authority == "" or authority:find("@", 1, true) then
    return nil
  end

  if authority:sub(1, 1) == "[" then
    local closing = authority:find("]", 2, true)
    if not closing then
      return nil
    end

    local host = authority:sub(2, closing - 1)
    local remainder = authority:sub(closing + 1)
    if remainder ~= "" and not remainder:match("^:%d+$") then
      return nil
    end

    return normalize_lower(host), remainder:match("^:(%d+)$")
  end

  local host, port = authority:match("^([^:]+):(%d+)$")
  if host then
    return normalize_lower(host), port
  end

  if authority:find(":", 1, true) then
    return nil
  end

  return normalize_lower(authority), nil
end

local function parse_origin(origin)
  if not origin or origin == "" or origin == "null" then
    return nil
  end

  local scheme, authority = origin:match("^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+)$")
  if not scheme or not authority then
    return nil
  end

  scheme = normalize_lower(scheme)
  if scheme ~= "http" and scheme ~= "https" then
    return nil
  end

  local host, port = split_authority(authority)
  if not host or host == "" then
    return nil
  end

  local normalized_authority = authority
  if authority:sub(1, 1) == "[" then
    normalized_authority = "[" .. host .. "]"
  else
    normalized_authority = host
  end

  if port then
    normalized_authority = normalized_authority .. ":" .. port
  end

  return {
    raw = origin,
    scheme = scheme,
    host = host,
    port = port,
    normalized = scheme .. "://" .. normalized_authority,
  }
end

local function to_lookup(values, normalizer)
  local lookup = {}

  for _, value in ipairs(values or {}) do
    local normalized = normalizer(value)
    if normalized and normalized ~= "" then
      lookup[normalized] = true
    end
  end

  return lookup
end

local function compile_config(conf)
  local compiled = compiled_config_cache[conf]
  if compiled then
    return compiled
  end

  compiled = {
    exact_origins = to_lookup(conf.allowed_origins, function(value)
      local parsed = parse_origin(value)
      return parsed and parsed.normalized or nil
    end),
    allowed_methods = to_lookup(conf.allow_methods, function(value)
      return value:upper()
    end),
    allowed_headers = to_lookup(conf.allow_headers, normalize_lower),
    allowed_host_suffixes = (function()
      local suffixes = {}

      for _, suffix in ipairs(conf.allowed_host_suffixes or {}) do
        local normalized = normalize_lower(suffix)
        if normalized and normalized ~= "" then
          suffixes[#suffixes + 1] = normalized:gsub("^%.+", "")
        end
      end

      return suffixes
    end)(),
    allow_methods_header = table.concat(conf.allow_methods, ", "),
    allow_headers_header = table.concat(conf.allow_headers, ", "),
    expose_headers_header = #conf.expose_headers > 0 and table.concat(conf.expose_headers, ", ") or nil,
  }

  compiled_config_cache[conf] = compiled
  return compiled
end

local function append_vary_token(existing, token)
  if not token or token == "" then
    return existing
  end

  if not existing or existing == "" then
    return token
  end

  local seen = {}
  local ordered = {}

  for entry in existing:gmatch("[^,]+") do
    local value = trim(entry)
    local lowered = value:lower()
    if value ~= "" and not seen[lowered] then
      seen[lowered] = true
      ordered[#ordered + 1] = value
    end
  end

  local lowered = token:lower()
  if not seen[lowered] then
    ordered[#ordered + 1] = token
  end

  return table.concat(ordered, ", ")
end

local function extend_vary(tokens)
  local vary = kong.response.get_header("Vary")

  for _, token in ipairs(tokens) do
    vary = append_vary_token(vary, token)
  end

  if vary then
    kong.response.set_header("Vary", vary)
  end
end

local function host_matches_suffix(host, suffixes)
  for _, suffix in ipairs(suffixes or {}) do
    if host == suffix or host:sub(-( #suffix + 1)) == "." .. suffix then
      return true
    end
  end

  return false
end

local function is_origin_allowed(conf, compiled, origin)
  if conf.allow_all_origins then
    return true
  end

  if compiled.exact_origins[origin.normalized] then
    return true
  end

  return host_matches_suffix(origin.host, compiled.allowed_host_suffixes)
end

local function is_method_allowed(compiled, method)
  return compiled.allowed_methods[(method or ""):upper()] == true
end

local function are_requested_headers_allowed(compiled, request_headers)
  if not request_headers or request_headers == "" then
    return true
  end

  for header in request_headers:gmatch("[^,]+") do
    local normalized = normalize_lower(trim(header))
    if normalized ~= "" and not compiled.allowed_headers[normalized] then
      return false
    end
  end

  return true
end

local function is_preflight()
  return kong.request.get_method() == "OPTIONS"
     and kong.request.get_header("Origin")
     and kong.request.get_header("Access-Control-Request-Method")
end

local function apply_allow_headers(conf, compiled, origin)
  if conf.allow_all_origins and not conf.allow_credentials then
    kong.response.set_header("Access-Control-Allow-Origin", "*")
  else
    kong.response.set_header("Access-Control-Allow-Origin", origin.raw)
    extend_vary(VARY_ORIGIN)
  end

  if conf.allow_credentials then
    kong.response.set_header("Access-Control-Allow-Credentials", "true")
  end

  if compiled.expose_headers_header then
    kong.response.set_header("Access-Control-Expose-Headers", compiled.expose_headers_header)
  end
end

local function apply_preflight_headers(conf, compiled, origin)
  apply_allow_headers(conf, compiled, origin)
  kong.response.set_header("Access-Control-Allow-Methods", compiled.allow_methods_header)
  kong.response.set_header("Access-Control-Allow-Headers", compiled.allow_headers_header)

  if conf.max_age > 0 then
    kong.response.set_header("Access-Control-Max-Age", tostring(conf.max_age))
  end

  if conf.allow_private_network
     and kong.request.get_header("Access-Control-Request-Private-Network") == "true" then
    kong.response.set_header("Access-Control-Allow-Private-Network", "true")
  end

  extend_vary(VARY_PREFLIGHT)
end

local function reject_or_silent_deny(conf, preflight)
  if preflight then
    extend_vary(VARY_PREFLIGHT)
  else
    extend_vary(VARY_ORIGIN)
  end

  if conf.reject_disallowed_origins then
    return kong.response.exit(conf.reject_status_code, {
      message = "CORS policy rejected the request",
    })
  end

  if preflight then
    return kong.response.exit(204)
  end
end

function plugin:access(conf)
  local compiled = compile_config(conf)
  local preflight = is_preflight()
  local origin_header = kong.request.get_header("Origin")

  if not origin_header then
    return
  end

  local origin = parse_origin(origin_header)
  if not origin then
    return reject_or_silent_deny(conf, preflight)
  end

  if not is_origin_allowed(conf, compiled, origin) then
    return reject_or_silent_deny(conf, preflight)
  end

  if preflight then
    local requested_method = kong.request.get_header("Access-Control-Request-Method")
    local requested_headers = kong.request.get_header("Access-Control-Request-Headers")
    local requested_private_network = kong.request.get_header("Access-Control-Request-Private-Network")

    if not is_method_allowed(compiled, requested_method) then
      return reject_or_silent_deny(conf, true)
    end

    if not are_requested_headers_allowed(compiled, requested_headers) then
      return reject_or_silent_deny(conf, true)
    end

    if requested_private_network == "true" and not conf.allow_private_network then
      return reject_or_silent_deny(conf, true)
    end

    apply_preflight_headers(conf, compiled, origin)
    return kong.response.exit(204)
  end

  kong.ctx.plugin.edge_cors_policy_origin = origin
end

function plugin:header_filter(conf)
  local origin = kong.ctx.plugin.edge_cors_policy_origin
  if not origin then
    return
  end

  apply_allow_headers(conf, compile_config(conf), origin)
end

return plugin
