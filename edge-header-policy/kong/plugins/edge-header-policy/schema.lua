local typedefs = require "kong.db.schema.typedefs"

local HEADER_NAME_PATTERN = "^[A-Za-z0-9-]+$"
local DEFAULT_MODE = "append"
local EMPTY_LIST = {}

local function validate_header_name(value)
  if not value:match(HEADER_NAME_PATTERN) then
    return nil, "must be a valid HTTP header name"
  end

  return true
end

local function validate_prefix(value)
  if not value:match("^[A-Za-z0-9-]+%-$") then
    return nil, "must end with '-' and contain only letters, digits, or '-'"
  end

  return true
end

return {
  name = "edge-header-policy",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            request_exact_mode = {
              type = "string",
              required = true,
              default = DEFAULT_MODE,
              one_of = { "append", "override" },
            },
          },
          {
            request_prefix_mode = {
              type = "string",
              required = true,
              default = DEFAULT_MODE,
              one_of = { "append", "override" },
            },
          },
          {
            response_exact_mode = {
              type = "string",
              required = true,
              default = DEFAULT_MODE,
              one_of = { "append", "override" },
            },
          },
          {
            response_prefix_mode = {
              type = "string",
              required = true,
              default = DEFAULT_MODE,
              one_of = { "append", "override" },
            },
          },
          {
            request_allow_headers = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_header_name,
              },
            },
          },
          {
            request_allow_prefixes = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_prefix,
              },
            },
          },
          {
            request_block_headers = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_header_name,
              },
            },
          },
          {
            request_block_prefixes = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_prefix,
              },
            },
          },
          {
            response_allow_headers = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_header_name,
              },
            },
          },
          {
            response_allow_prefixes = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_prefix,
              },
            },
          },
          {
            response_block_headers = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_header_name,
              },
            },
          },
          {
            response_block_prefixes = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "string",
                custom_validator = validate_prefix,
              },
            },
          },
          {
            static_request_headers = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "record",
                fields = {
                  { header = { type = "string", required = true, custom_validator = validate_header_name } },
                  { value = { type = "string", required = true } },
                  { overwrite = { type = "boolean", required = true, default = true } },
                },
              },
            },
          },
          {
            static_response_headers = {
              type = "array",
              required = true,
              default = EMPTY_LIST,
              elements = {
                type = "record",
                fields = {
                  { header = { type = "string", required = true, custom_validator = validate_header_name } },
                  { value = { type = "string", required = true } },
                  { overwrite = { type = "boolean", required = true, default = true } },
                },
              },
            },
          },
        },
      },
    },
  },
}
