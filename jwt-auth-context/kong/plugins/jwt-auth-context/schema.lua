local typedefs = require "kong.db.schema.typedefs"

local function validate_header_name(value)
  if not value:match("^[A-Za-z0-9-]+$") then
    return nil, "must be a valid HTTP header name"
  end

  return true
end

local function validate_json_path(value)
  if not value:match("^%$%.[A-Za-z0-9_%.%-]+$") then
    return nil, "must be a simple JSON path like $.sub or $.realm_access.roles"
  end

  return true
end

return {
  name = "jwt-auth-context",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          { jwks_url = typedefs.url({ required = true }) },
          { jwks_cache_ttl_seconds = { type = "integer", required = true, default = 300, between = { 30, 3600 } } },
          { connect_timeout_ms = { type = "integer", required = true, default = 2000, between = { 100, 10000 } } },
          { send_timeout_ms = { type = "integer", required = true, default = 2000, between = { 100, 10000 } } },
          { read_timeout_ms = { type = "integer", required = true, default = 3000, between = { 100, 20000 } } },
          { ssl_verify = { type = "boolean", required = true, default = true } },
          { clock_skew_seconds = { type = "integer", required = true, default = 60, between = { 0, 300 } } },
          { expected_issuer = { type = "string", required = false } },
          { expected_audience = { type = "string", required = false } },
          { require_email_verified = { type = "boolean", required = true, default = false } },
          { required_role = { type = "string", required = false } },
          { on_missing_token = { type = "string", required = true, default = "reject", one_of = { "pass", "reject", "redirect" } } },
          { on_invalid_token = { type = "string", required = true, default = "reject", one_of = { "reject", "redirect" } } },
          { browser_redirect_url = typedefs.url({ required = false }) },
          { browser_redirect_only = { type = "boolean", required = true, default = true } },
          { token_sources = { type = "array", required = true, default = { "authorization" }, elements = { type = "string", one_of = { "authorization", "cookie", "query" } } } },
          { cookie_name = { type = "string", required = true, default = "access_token" } },
          { query_param_name = { type = "string", required = true, default = "access_token" } },
          {
            custom_header_mappings = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "record",
                fields = {
                  { header = { type = "string", required = true, custom_validator = validate_header_name } },
                  { claim_path = { type = "string", required = true, custom_validator = validate_json_path } },
                  { required = { type = "boolean", required = true, default = false } },
                  { json_encode = { type = "boolean", required = true, default = false } },
                },
              },
            },
          },
        },
        custom_validator = function(config)
          if (config.on_missing_token == "redirect" or config.on_invalid_token == "redirect")
             and not config.browser_redirect_url then
            return nil, "browser_redirect_url is required when redirect behavior is enabled"
          end

          return true
        end,
      },
    },
  },
}
