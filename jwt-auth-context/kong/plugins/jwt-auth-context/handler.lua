local cjson = require "cjson.safe"
local http = require "resty.http"
local jwt = require "resty.jwt"
local x509 = require "resty.openssl.x509"
local pkey = require "resty.openssl.pkey"

local kong = kong
local ngx = ngx

local plugin = {
  PRIORITY = 2200,
  VERSION = "1.0.0",
}

local DEFAULT_MAPPINGS = {
  { header = "x-auth-token-user-id", claim_path = "$.sub" },
  { header = "x-auth-token-email", claim_path = "$.email" },
  { header = "x-auth-token-preferred-username", claim_path = "$.preferred_username" },
  { header = "x-auth-token-name", claim_path = "$.name" },
  { header = "x-auth-token-given-name", claim_path = "$.given_name" },
  { header = "x-auth-token-family-name", claim_path = "$.family_name" },
  { header = "x-auth-token-scope", claim_path = "$.scope" },
  { header = "x-auth-token-email-verified", claim_path = "$.email_verified" },
}

local compiled_cache = setmetatable({}, { __mode = "k" })

local function log_event(level, code, message, extra)
  local payload = {
    plugin = "jwt-auth-context",
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

local function normalize_header_name(value)
  return value and value:lower() or nil
end

local function normalize_mapping(mapping, required, json_encode)
  return {
    header = normalize_header_name(mapping.header),
    claim_path = mapping.claim_path,
    required = required,
    json_encode = json_encode,
  }
end

local function compile_config(conf)
  local compiled = compiled_cache[conf]
  if compiled then
    return compiled
  end

  compiled = {
    mappings = {},
    cleared_headers = {},
  }

  for _, mapping in ipairs(DEFAULT_MAPPINGS) do
    local normalized = normalize_mapping(mapping, false, false)
    compiled.mappings[#compiled.mappings + 1] = normalized
    compiled.cleared_headers[#compiled.cleared_headers + 1] = normalized.header
  end

  for _, mapping in ipairs(conf.custom_header_mappings) do
    local normalized = normalize_mapping(mapping, mapping.required, mapping.json_encode)
    compiled.mappings[#compiled.mappings + 1] = normalized
    compiled.cleared_headers[#compiled.cleared_headers + 1] = normalized.header
  end

  compiled_cache[conf] = compiled
  return compiled
end

local function clear_headers(compiled)
  for _, header in ipairs(compiled.cleared_headers) do
    kong.service.request.clear_header(header)
  end
end

local function is_browser_request()
  local accept = kong.request.get_header("accept") or ""
  return accept:find("text/html", 1, true) ~= nil
end

local function maybe_redirect(conf, reason)
  if not conf.browser_redirect_url then
    return false
  end

  if conf.browser_redirect_only and not is_browser_request() then
    return false
  end

  return kong.response.exit(302, nil, {
    Location = conf.browser_redirect_url,
    ["Cache-Control"] = "no-store",
    ["X-Auth-Redirect-Reason"] = reason,
  })
end

local function reject(status, code, message)
  return kong.response.exit(status, {
    message = message,
    code = code,
  })
end

local function read_cookie(name)
  local cookie = kong.request.get_header("cookie")
  if not cookie then
    return nil
  end

  for key, value in cookie:gmatch("([^=;,%s]+)=([^;,%s]+)") do
    if key == name then
      return value
    end
  end

  return nil
end

local function extract_token(conf)
  for _, source in ipairs(conf.token_sources) do
    if source == "authorization" then
      local header = kong.request.get_header("authorization")
      if header then
        local token = header:match("^[Bb]earer%s+(.+)$")
        if token then
          return token, source
        end
      end
    elseif source == "cookie" then
      local token = read_cookie(conf.cookie_name)
      if token and token ~= "" then
        return token, source
      end
    elseif source == "query" then
      local token = kong.request.get_query_arg(conf.query_param_name)
      if token and token ~= "" then
        return token, source
      end
    end
  end

  return nil
end

local function fetch_jwks(conf)
  local cache_key = "jwt-auth-context:jwks:" .. conf.jwks_url

  return kong.cache:get(cache_key, { ttl = conf.jwks_cache_ttl_seconds }, function()
    local client = http.new()
    client:set_timeouts(conf.connect_timeout_ms, conf.send_timeout_ms, conf.read_timeout_ms)

    local response, err = client:request_uri(conf.jwks_url, {
      method = "GET",
      ssl_verify = conf.ssl_verify,
      headers = { Accept = "application/json" },
    })

    if not response then
      return nil, "jwks_request_failed:" .. tostring(err)
    end

    if response.status ~= 200 then
      return nil, "jwks_http_status:" .. tostring(response.status)
    end

    local body = cjson.decode(response.body or "")
    if not body or type(body.keys) ~= "table" then
      return nil, "jwks_invalid_payload"
    end

    return body
  end)
end

local function parse_unverified(token)
  local parsed = jwt:load_jwt(token)
  if not parsed.valid then
    return nil, parsed.reason or "malformed_jwt"
  end

  return parsed
end

local function jwk_to_pem(jwk_key)
  if type(jwk_key.x5c) == "table" and jwk_key.x5c[1] then
    local cert_pem = "-----BEGIN CERTIFICATE-----\n"
      .. jwk_key.x5c[1]
      .. "\n-----END CERTIFICATE-----\n"
    local cert = assert(x509.new(cert_pem))
    local public_key = assert(cert:get_pubkey())
    return assert(public_key:to_PEM("public"))
  end

  if jwk_key.kty == "RSA" and jwk_key.n and jwk_key.e then
    local key = assert(pkey.new({
      kty = jwk_key.kty,
      n = jwk_key.n,
      e = jwk_key.e,
    }))
    return assert(key:to_PEM("public"))
  end

  return nil, "unsupported_jwk_material"
end

local function select_jwk(jwks, kid)
  if not jwks or type(jwks.keys) ~= "table" then
    return nil
  end

  if kid then
    for _, key in ipairs(jwks.keys) do
      if key.kid == kid then
        return key
      end
    end
  end

  return jwks.keys[1]
end

local function array_contains(values, target)
  if type(values) ~= "table" then
    return false
  end

  for _, value in ipairs(values) do
    if value == target then
      return true
    end
  end

  return false
end

local function verify_token(conf, token)
  local parsed, parse_err = parse_unverified(token)
  if not parsed then
    return nil, parse_err
  end

  local jwks, jwks_err = fetch_jwks(conf)
  if not jwks then
    return nil, jwks_err
  end

  local jwk_key = select_jwk(jwks, parsed.header.kid)
  if not jwk_key then
    return nil, "kid_not_found"
  end

  local pem, pem_err = jwk_to_pem(jwk_key)
  if not pem then
    return nil, pem_err
  end

  local verified = jwt:verify(pem, token)
  if not verified.verified then
    return nil, verified.reason or "jwt_verification_failed"
  end

  local now = ngx.time()
  local exp = tonumber(verified.payload.exp)
  if exp and now > (exp + conf.clock_skew_seconds) then
    return nil, "token_expired"
  end

  local nbf = tonumber(verified.payload.nbf)
  if nbf and now < (nbf - conf.clock_skew_seconds) then
    return nil, "token_not_yet_valid"
  end

  if conf.expected_issuer and verified.payload.iss ~= conf.expected_issuer then
    return nil, "issuer_mismatch"
  end

  if conf.expected_audience then
    local aud = verified.payload.aud
    if type(aud) == "table" then
      if not array_contains(aud, conf.expected_audience) then
        return nil, "audience_mismatch"
      end
    elseif aud ~= conf.expected_audience then
      return nil, "audience_mismatch"
    end
  end

  return verified.payload
end

local function read_path(source, path)
  local current = source
  for part in path:gmatch("[^.]+") do
    if part ~= "$" then
      if type(current) ~= "table" then
        return nil
      end
      current = current[part]
    end
  end
  return current
end

local function ensure_role(payload, required_role)
  if not required_role or required_role == "" then
    return true
  end

  if array_contains(read_path(payload, "$.realm_access.roles"), required_role) then
    return true
  end

  if array_contains(read_path(payload, "$.roles"), required_role) then
    return true
  end

  return false
end

local function write_value(header, value, json_encode)
  if value == nil or value == cjson.null then
    kong.service.request.clear_header(header)
    return
  end

  if type(value) == "table" then
    if json_encode then
      kong.service.request.set_header(header, cjson.encode(value))
    else
      kong.service.request.set_header(header, table.concat(value, ","))
    end
    return
  end

  kong.service.request.set_header(header, tostring(value))
end

function plugin:access(conf)
  local compiled = compile_config(conf)
  clear_headers(compiled)

  local token, source = extract_token(conf)
  if not token then
    if conf.on_missing_token == "pass" then
      return
    end

    if conf.on_missing_token == "redirect" then
      return maybe_redirect(conf, "missing_token")
    end

    return reject(401, "MISSING_TOKEN", "JWT token is required")
  end

  local payload, verify_err = verify_token(conf, token)
  if not payload then
    log_event("err", "TOKEN_VERIFICATION_FAILED", "JWT verification failed", {
      reason = verify_err,
      token_source = source,
    })

    if conf.on_invalid_token == "redirect" then
      return maybe_redirect(conf, "invalid_token")
    end

    return reject(401, "INVALID_TOKEN", "JWT token is invalid")
  end

  if conf.require_email_verified and payload.email_verified ~= true then
    return reject(401, "EMAIL_NOT_VERIFIED", "Verified email is required")
  end

  if not ensure_role(payload, conf.required_role) then
    return reject(403, "ROLE_REQUIRED", "Required role is missing")
  end

  for _, mapping in ipairs(compiled.mappings) do
    local value = read_path(payload, mapping.claim_path)
    if mapping.required and (value == nil or value == cjson.null) then
      return reject(401, "REQUIRED_CLAIM_MISSING", "Required claim is missing")
    end
    write_value(mapping.header, value, mapping.json_encode)
  end
end

return plugin
