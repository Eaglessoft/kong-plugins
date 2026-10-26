-- The actual plugin runs against deterministic Kong and provider doubles.
package.path = "/usr/local/openresty/lualib/?.lua;/usr/local/openresty/lualib/?/init.lua;" .. package.path
package.cpath = "/usr/local/openresty/lualib/?.so;" .. package.cpath
local cjson = require "cjson.safe"
local state
local TOKEN = "issued.test.token"
local SECRET = "test-only secret&=+%"

local function equal(actual, expected, label)
  assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function form_encode(values)
  local parts = {}
  local function escape(value)
    return (value:gsub("[^A-Za-z0-9_.~-]", function(char)
      return string.format("%%%02X", string.byte(char))
    end))
  end
  for key, value in pairs(values) do
    parts[#parts + 1] = escape(key) .. "=" .. escape(value)
  end
  return table.concat(parts, "&")
end

_G.ngx = { time = function() return 1000 end, encode_args = form_encode }
_G.kong = {
  request = {
    get_header = function(name)
      local value = state.headers[name:lower()]
      return type(value) == "table" and value[1] or value
    end,
    get_headers = function() return state.headers, state.headers_error end,
    get_query_arg = function(name) return state.query[name] end,
  },
  service = { request = {
    clear_header = function(name) state.headers[name:lower()] = nil end,
    set_header = function(name, value) state.headers[name:lower()] = value end,
  } },
  response = { exit = function(status, body, headers)
    state.response = { status = status, body = body, headers = headers }
    error("response_exit", 0)
  end },
  log = {
    err = function(message) state.logs[#state.logs + 1] = message end,
    warn = function(message) state.logs[#state.logs + 1] = message end,
  },
  cache = { get = function(_, _, _, callback) return callback() end },
}

package.preload["resty.http"] = function()
  return { new = function()
    return {
      set_timeouts = function(_, connect, send, read)
        state.timeouts = { connect, send, read }
      end,
      request_uri = function(_, url, options)
        if options.method == "POST" then
          state.exchanges[#state.exchanges + 1] = { url = url, options = options }
          return state.token_response, state.http_error
        end
        state.jwks_calls = state.jwks_calls + 1
        return { status = 200, body = cjson.encode({ keys = {
          { kid = "test-key", kty = "RSA", n = "test-n", e = "AQAB" },
        } }) }
      end,
    }
  end }
end

package.preload["resty.jwt"] = function()
  return {
    load_jwt = function(_, token)
      state.parsed_token = token
      return { valid = not state.malformed, header = { kid = "test-key" }, reason = TOKEN }
    end,
    verify = function(_, _, token)
      state.verified_token = token
      return { verified = not state.bad_signature, payload = state.payload, reason = TOKEN }
    end,
  }
end
package.preload["resty.openssl.x509"] = function() return {} end
package.preload["resty.openssl.pkey"] = function()
  return { new = function() return { to_PEM = function() return "test-public-key" end } end }
end

package.preload["kong.db.schema.typedefs"] = function()
  return { url = function(options) return options end, no_consumer = {}, protocols_http = {} }
end

local root = "jwt-auth-context/kong/plugins/jwt-auth-context/"
local plugin = assert(loadfile(root .. "handler.lua"))()
local schema = assert(loadfile(root .. "schema.lua"))()
local config_schema = schema.fields[3].config

local function reset()
  state = {
    headers = {}, query = {}, logs = {}, exchanges = {}, jwks_calls = 0,
    token_response = { status = 200, body = cjson.encode({ access_token = TOKEN, token_type = "Bearer" }) },
    payload = { sub = "service-account-id", exp = 1100, nbf = 900,
      iss = "https://sso.example/realms/test", aud = "gateway", email_verified = true,
      realm_access = { roles = { "hook-user" } } },
  }
  local config = {}
  for _, entry in ipairs(config_schema.fields) do
    for name, field in pairs(entry) do
      if field.default ~= nil then config[name] = field.default end
    end
  end
  config.jwks_url = "https://sso.example/realms/test/certs"
  config.token_endpoint_url = "https://sso.example/realms/test/token"
  config.expected_issuer = state.payload.iss
  config.expected_audience = "gateway"
  config.client_credentials_enabled = true
  config.require_email_verified = true
  config.required_role = "hook-user"
  config.custom_header_mappings = {}
  return config
end

local function credentials()
  state.headers["x-client-id"] = "client &+"
  state.headers["x-api-key"] = SECRET
end

local function run(config, expected_status)
  local ok, err = pcall(plugin.access, plugin, config)
  if not ok then equal(err, "response_exit", "unexpected exception") end
  equal(state.response and state.response.status, expected_status, "response status")
  local exposed = cjson.encode({ logs = state.logs, response = state.response }) or ""
  assert(not exposed:find(SECRET, 1, true), "secret leaked")
  assert(not exposed:find(TOKEN, 1, true), "issued token leaked")
end

local passed = 0
local function test(name, action)
  action()
  passed = passed + 1
  print("PASS " .. name)
end

test("client credentials are opt-in", function()
  local enabled
  for _, field in ipairs(config_schema.fields) do
    if field.client_credentials_enabled then enabled = field.client_credentials_enabled.default end
  end
  equal(enabled, false)
end)

test("Bearer works without calling the token endpoint", function()
  local config = reset()
  state.headers.authorization = "Bearer incoming.jwt"
  run(config)
  equal(#state.exchanges, 0)
  equal(state.headers["x-auth-token-user-id"], "service-account-id")
  equal(state.headers.authorization, "Bearer incoming.jwt")
end)

test("disabled feature preserves JWT-only missing policy", function()
  local config = reset(); config.client_credentials_enabled = false
  credentials(); run(config, 401); equal(#state.exchanges, 0)
end)

test("exchanged token uses common verification and upstream headers", function()
  local config = reset(); credentials()
  config.custom_header_mappings = { { header = "X-Auth-Roles", claim_path = "$.realm_access.roles", json_encode = true } }
  run(config)
  equal(state.parsed_token, TOKEN); equal(state.verified_token, TOKEN)
  equal(state.headers.authorization, "Bearer " .. TOKEN)
  equal(state.headers["x-auth-token-user-id"], state.payload.sub)
  equal(state.headers["x-auth-roles"], '["hook-user"]')
  equal(state.headers["x-api-key"], nil); equal(state.headers["x-client-id"], nil)
  local exchange = state.exchanges[1]
  equal(exchange.url, config.token_endpoint_url)
  equal(exchange.options.headers["Content-Type"], "application/x-www-form-urlencoded")
  equal(exchange.options.ssl_verify, true)
  equal(exchange.options.ssl_server_name, "sso.example")
  equal(state.timeouts[1], config.connect_timeout_ms)
  assert(exchange.options.body:find("client_id=client%20%26%2B", 1, true))
  assert(exchange.options.body:find("client_secret=test-only%20secret%26%3D%2B%25", 1, true))
  assert(exchange.options.body:find("grant_type=client_credentials", 1, true))
end)

test("custom credential headers are supported and removed", function()
  local config = reset(); config.client_id_header = "X-App"; config.client_secret_header = "X-Key"
  state.headers["x-app"] = "app"; state.headers["x-key"] = SECRET
  run(config); equal(state.headers["x-app"], nil); equal(state.headers["x-key"], nil)
end)

for _, source in ipairs({ "authorization", "cookie", "query" }) do
  test("mixed credentials rejected for " .. source, function()
    local config = reset(); config.token_sources = { source }; credentials()
    if source == "authorization" then state.headers.authorization = "Bearer incoming.jwt"
    elseif source == "cookie" then state.headers.cookie = "access_token=incoming.jwt"
    else state.query.access_token = "incoming.jwt" end
    run(config, 400); equal(#state.exchanges, 0)
  end)
end

for _, value in ipairs({ "", "   ", "line\r\nbreak", { "one", "two" } }) do
  test("malformed client secret rejected: " .. type(value), function()
    local config = reset(); credentials(); state.headers["x-api-key"] = value
    run(config, 401); equal(#state.exchanges, 0)
  end)
end

test("partial and duplicate client IDs are rejected", function()
  local config = reset(); credentials(); state.headers["x-api-key"] = nil
  run(config, 401)
  config = reset(); credentials(); state.headers["x-client-id"] = { "one", "two" }
  run(config, 401)
end)

test("malformed Authorization cannot fall back to credentials", function()
  local config = reset(); credentials(); state.headers.authorization = "Bearer "
  run(config, 400); equal(#state.exchanges, 0)
end)

test("invalid Bearer cannot fall back", function()
  local config = reset(); state.headers.authorization = "Bearer invalid.jwt"; state.payload.exp = 1
  run(config, 401); equal(#state.exchanges, 0)
end)

for _, source in ipairs({ "cookie", "query" }) do
  test("legacy " .. source .. " source still works", function()
    local config = reset(); config.client_credentials_enabled = false; config.token_sources = { source }
    if source == "cookie" then state.headers.cookie = "access_token=incoming.jwt"
    else state.query.access_token = "incoming.jwt" end
    run(config); equal(state.verified_token, "incoming.jwt")
  end)
end

for _, policy in ipairs({ "pass", "reject", "redirect" }) do
  test("missing token policy: " .. policy, function()
    local config = reset(); config.on_missing_token = policy; config.browser_redirect_url = "https://login.example"
    state.headers.accept = "text/html"
    run(config, ({ reject = 401, redirect = 302 })[policy])
  end)
end

for _, failure in ipairs({ "expired", "nbf", "issuer", "audience", "email", "role", "signature", "malformed" }) do
  test("issued token checks: " .. failure, function()
    local config = reset(); credentials()
    if failure == "expired" then state.payload.exp = 1
    elseif failure == "nbf" then state.payload.nbf = 2000
    elseif failure == "issuer" then state.payload.iss = "https://other.example"
    elseif failure == "audience" then state.payload.aud = "other"
    elseif failure == "email" then state.payload.email_verified = false
    elseif failure == "role" then state.payload.realm_access.roles = {}
    elseif failure == "signature" then state.bad_signature = true
    else state.malformed = true end
    run(config, failure == "role" and 403 or 401)
    equal(state.headers.authorization, nil)
  end)
end

for _, failure in ipairs({ "invalid_client", "unauthorized_client", "401", "500", "redirect", "timeout", "json", "scalar", "empty", "type", "whitespace" }) do
  test("token endpoint failure: " .. failure, function()
    local config = reset(); credentials()
    if failure == "invalid_client" or failure == "unauthorized_client" then
      state.token_response = { status = 400, body = cjson.encode({ error = failure, error_description = SECRET }) }
    elseif failure == "401" then state.token_response = { status = 401, body = SECRET }
    elseif failure == "500" then state.token_response = { status = 500, body = SECRET }
    elseif failure == "redirect" then state.token_response = { status = 302, body = SECRET }
    elseif failure == "timeout" then state.token_response = nil; state.http_error = SECRET
    elseif failure == "json" then state.token_response.body = "invalid-json" .. SECRET
    elseif failure == "scalar" then state.token_response.body = "42"
    elseif failure == "empty" then state.token_response.body = '{}'
    elseif failure == "type" then state.token_response.body = cjson.encode({ access_token = TOKEN, token_type = "MAC" })
    else state.token_response.body = cjson.encode({ access_token = TOKEN .. "\r\n", token_type = "Bearer" }) end
    run(config, (failure == "invalid_client" or failure == "unauthorized_client" or failure == "401") and 401 or 502)
    equal(#state.exchanges, 1); equal(state.jwks_calls, 0)
  end)
end

test("exchanges are not cached", function()
  local config = reset(); credentials(); run(config)
  state.headers.authorization = nil; credentials(); run(config)
  equal(#state.exchanges, 2)
end)

test("truncated credential headers fail closed", function()
  local config = reset(); credentials(); state.headers_error = "truncated"
  run(config, 401); equal(#state.exchanges, 0)
end)

test("required custom claims still reject issued token", function()
  local config = reset(); credentials()
  config.custom_header_mappings = { { header = "X-Required", claim_path = "$.missing", required = true } }
  run(config, 401); equal(state.headers.authorization, nil)
end)

test("schema validates endpoint and credential header isolation", function()
  local validate = config_schema.custom_validator
  local config = reset(); assert(validate(config))
  for _, endpoint in ipairs({ "", "http://sso.example/token", "https://user:password@sso.example/token", "https://sso.example/token#fragment" }) do
    config.token_endpoint_url = endpoint; assert(not validate(config))
  end
  config = reset(); config.token_endpoint_url = nil; assert(not validate(config))
  config.client_credentials_enabled = false; assert(validate(config))
  for _, header in ipairs({ "Authorization", "Cookie", "Host", "X-Auth-Token-User-Id", "X-Company-Id", "X-Subscription-Id", "X-Hasura-Role", "X-API-Key" }) do
    config = reset(); config.client_id_header = header; assert(not validate(config), header)
  end
  config = reset(); config.custom_header_mappings = { { header = "X-API-Key" } }
  assert(not validate(config))
end)

test("existing redirect schema validation remains active", function()
  local config = reset(); config.on_missing_token = "redirect"
  assert(not config_schema.custom_validator(config))
end)

print(string.format("%d focused plugin tests passed", passed))
