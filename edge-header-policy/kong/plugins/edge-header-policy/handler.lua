local kong = kong

local plugin = {
  PRIORITY = 3000,
  VERSION = "1.0.0",
}

local compiled_cache = setmetatable({}, { __mode = "k" })

local DEFAULT_REQUEST_BLOCK_HEADERS = {
  "x-authenticated-scope",
  "x-consumer-id",
  "x-consumer-groups",
  "x-consumer-username",
  "x-credential-identifier",
  "x-real-ip",
}

local DEFAULT_REQUEST_BLOCK_PREFIXES = {
  "x-auth-",
  "x-user-",
  "x-company-",
  "x-subscription-",
  "x-hasura-",
  "x-actor-",
}

local DEFAULT_RESPONSE_BLOCK_HEADERS = {
  "origin",
  "server",
  "x-kong-proxy-latency",
  "x-kong-request-id",
  "x-kong-response-latency",
  "x-powered-by",
  "x-upstream-status",
}

local DEFAULT_RESPONSE_BLOCK_PREFIXES = {
  "x-auth-",
  "x-hasura-",
  "x-internal-",
}

local function normalize_lower(value)
  return value and value:lower() or nil
end

local function contains_prefix(name, prefixes)
  for _, prefix in ipairs(prefixes) do
    if name:sub(1, #prefix) == prefix then
      return true
    end
  end

  return false
end

local function build_exact_set(mode, defaults, extras)
  local set = {}

  if mode == "append" then
    for _, name in ipairs(defaults) do
      set[name] = true
    end
  end

  for _, name in ipairs(extras or {}) do
    set[normalize_lower(name)] = true
  end

  return set
end

local function build_prefixes(mode, defaults, extras)
  local ordered = {}
  local seen = {}

  if mode == "append" then
    for _, value in ipairs(defaults) do
      local normalized = normalize_lower(value)
      if not seen[normalized] then
        seen[normalized] = true
        ordered[#ordered + 1] = normalized
      end
    end
  end

  for _, value in ipairs(extras or {}) do
    local normalized = normalize_lower(value)
    if not seen[normalized] then
      seen[normalized] = true
      ordered[#ordered + 1] = normalized
    end
  end

  return ordered
end

local function build_allow_set(values)
  local set = {}

  for _, name in ipairs(values or {}) do
    set[normalize_lower(name)] = true
  end

  return set
end

local function build_compiled(conf)
  local compiled = compiled_cache[conf]
  if compiled then
    return compiled
  end

  compiled = {
    request_allow_headers = build_allow_set(conf.request_allow_headers),
    request_allow_prefixes = build_prefixes("override", {}, conf.request_allow_prefixes),
    request_block_headers = build_exact_set(conf.request_exact_mode, DEFAULT_REQUEST_BLOCK_HEADERS, conf.request_block_headers),
    request_block_prefixes = build_prefixes(conf.request_prefix_mode, DEFAULT_REQUEST_BLOCK_PREFIXES, conf.request_block_prefixes),
    response_allow_headers = build_allow_set(conf.response_allow_headers),
    response_allow_prefixes = build_prefixes("override", {}, conf.response_allow_prefixes),
    response_block_headers = build_exact_set(conf.response_exact_mode, DEFAULT_RESPONSE_BLOCK_HEADERS, conf.response_block_headers),
    response_block_prefixes = build_prefixes(conf.response_prefix_mode, DEFAULT_RESPONSE_BLOCK_PREFIXES, conf.response_block_prefixes),
  }

  compiled_cache[conf] = compiled
  return compiled
end

local function is_allowed(name, exact_allow, prefix_allow)
  return exact_allow[name] or contains_prefix(name, prefix_allow)
end

local function should_block(name, exact_allow, prefix_allow, exact_block, prefix_block)
  if is_allowed(name, exact_allow, prefix_allow) then
    return false
  end

  return exact_block[name] or contains_prefix(name, prefix_block)
end

function plugin:access(conf)
  local compiled = build_compiled(conf)
  local headers = kong.request.get_headers()

  for name in pairs(headers) do
    local normalized = normalize_lower(name)
    if should_block(
      normalized,
      compiled.request_allow_headers,
      compiled.request_allow_prefixes,
      compiled.request_block_headers,
      compiled.request_block_prefixes
    ) then
      kong.service.request.clear_header(name)
    end
  end
end

function plugin:header_filter(conf)
  local compiled = build_compiled(conf)
  local headers = kong.response.get_headers()

  if not headers then
    return
  end

  for name in pairs(headers) do
    local normalized = normalize_lower(name)
    if should_block(
      normalized,
      compiled.response_allow_headers,
      compiled.response_allow_prefixes,
      compiled.response_block_headers,
      compiled.response_block_prefixes
    ) then
      kong.response.clear_header(name)
    end
  end
end

return plugin
