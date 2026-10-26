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
          { client_credentials_enabled = { type = "boolean", required = true, default = false } },
          { token_endpoint_url = typedefs.url({ required = false }) },
          { client_id_header = { type = "string", required = true, default = "X-Client-Id", custom_validator = validate_header_name } },
          { client_secret_header = { type = "string", required = true, default = "X-API-Key", custom_validator = validate_header_name } },
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

          if config.client_credentials_enabled then
            local authority = type(config.token_endpoint_url) == "string"
              and config.token_endpoint_url:match("^https://([^/?#]+)")
            if not authority or authority:find("@", 1, true) or config.token_endpoint_url:find("#", 1, true) then
              return nil, "an HTTPS token_endpoint_url without userinfo or fragment is required for client credentials"
            end

            local id_header, secret_header = config.client_id_header:lower(), config.client_secret_header:lower()
            if id_header == secret_header then
              return nil, "client credential headers must be different"
            end

            local reserved = {
              authorization = true, cookie = true, host = true,
              ["content-type"] = true, ["content-length"] = true,
              connection = true, ["proxy-authorization"] = true,
              ["transfer-encoding"] = true, ["keep-alive"] = true,
              te = true, trailer = true, upgrade = true,
            }
            for _, header in ipairs({ id_header, secret_header }) do
              if reserved[header] or header:match("^x%-auth%-")
                 or header:match("^x%-company%-") or header:match("^x%-subscription%-")
                 or header:match("^x%-hasura%-") then
                return nil, "client credential headers must not replace authentication or routing headers"
              end
              for _, mapping in ipairs(config.custom_header_mappings or {}) do
                if header == mapping.header:lower() then
                  return nil, "client credential headers must not overlap custom_header_mappings"
                end
              end
            end
          end

          return true
        end,
      },
    },
  },
}
