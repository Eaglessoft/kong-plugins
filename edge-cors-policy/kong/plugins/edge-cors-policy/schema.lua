local typedefs = require "kong.db.schema.typedefs"

local function validate_origin(value)
  if value == "*" then
    return nil, "use allow_all_origins=true instead of '*' in allowed_origins"
  end

  if not value:match("^https?://") then
    return nil, "must start with http:// or https://"
  end

  if value:find("[/%?#]") then
    return nil, "must not contain path, query, or fragment"
  end

  if value:find("@", 1, true) then
    return nil, "must not contain userinfo"
  end

  return true
end

local function validate_host_suffix(value)
  if value == "" then
    return nil, "must not be empty"
  end

  if value:find("[%s:/%?#@]") then
    return nil, "must be a hostname suffix without scheme, path, or port"
  end

  return true
end

return {
  name = "edge-cors-policy",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            allow_all_origins = {
              type = "boolean",
              required = true,
              default = false,
            },
          },
          {
            allowed_origins = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "string",
                custom_validator = validate_origin,
              },
            },
          },
          {
            allowed_host_suffixes = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "string",
                custom_validator = validate_host_suffix,
              },
            },
          },
          {
            allow_methods = {
              type = "array",
              required = true,
              default = { "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS" },
              elements = {
                type = "string",
                one_of = { "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS" },
              },
            },
          },
          {
            allow_headers = {
              type = "array",
              required = true,
              default = { "Accept", "Authorization", "Content-Type", "Origin", "X-Requested-With" },
              elements = { type = "string" },
            },
          },
          {
            expose_headers = {
              type = "array",
              required = true,
              default = {},
              elements = { type = "string" },
            },
          },
          {
            allow_credentials = {
              type = "boolean",
              required = true,
              default = false,
            },
          },
          {
            max_age = {
              type = "integer",
              required = true,
              default = 600,
              between = { 0, 86400 },
            },
          },
          {
            reject_disallowed_origins = {
              type = "boolean",
              required = true,
              default = true,
            },
          },
          {
            reject_status_code = {
              type = "integer",
              required = true,
              default = 403,
              one_of = { 401, 403 },
            },
          },
          {
            allow_private_network = {
              type = "boolean",
              required = true,
              default = false,
            },
          },
        },
        custom_validator = function(config)
          if config.allow_all_origins and config.allow_credentials then
            return nil, "allow_all_origins cannot be combined with allow_credentials=true"
          end

          if not config.allow_all_origins
             and #config.allowed_origins == 0
             and #config.allowed_host_suffixes == 0 then
            return nil, "configure allowed_origins or allowed_host_suffixes, or enable allow_all_origins"
          end

          return true
        end,
      },
    },
  },
}
