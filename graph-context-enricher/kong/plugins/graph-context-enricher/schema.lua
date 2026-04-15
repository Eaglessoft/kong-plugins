local typedefs = require "kong.db.schema.typedefs"

local function validate_header_name(value)
  if not value:match("^[A-Za-z0-9-]+$") then
    return nil, "must be a valid HTTP header name"
  end

  return true
end

local function validate_json_path(value)
  if not value:match("^%$%.[A-Za-z0-9_%.%-]+$") then
    return nil, "must be a simple JSON path like $.data.company.id"
  end

  return true
end

local function validate_variable_name(value)
  if not value:match("^[A-Za-z_][A-Za-z0-9_]*$") then
    return nil, "must be a valid GraphQL variable name"
  end

  return true
end

return {
  name = "graph-context-enricher",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          { graph_url = typedefs.url({ required = true }) },
          { graph_query = { type = "string", required = true, default = "" } },
          { connect_timeout_ms = { type = "integer", required = true, default = 1000, between = { 100, 10000 } } },
          { send_timeout_ms = { type = "integer", required = true, default = 1000, between = { 100, 10000 } } },
          { read_timeout_ms = { type = "integer", required = true, default = 3000, between = { 100, 20000 } } },
          { retries = { type = "integer", required = true, default = 0, between = { 0, 2 } } },
          { ssl_verify = { type = "boolean", required = true, default = true } },
          { on_upstream_error = { type = "string", required = true, default = "reject", one_of = { "reject", "pass" } } },
          { on_missing_data = { type = "string", required = true, default = "reject", one_of = { "reject", "pass" } } },
          { on_multiple_results = { type = "string", required = true, default = "reject", one_of = { "reject", "pass", "first" } } },
          {
            variable_mappings = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "record",
                fields = {
                  { variable = { type = "string", required = true, custom_validator = validate_variable_name } },
                  { from_header = { type = "string", required = true, custom_validator = validate_header_name } },
                  { required = { type = "boolean", required = true, default = true } },
                },
              },
            },
          },
          {
            forward_headers = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "string",
                custom_validator = validate_header_name,
              },
            },
          },
          {
            static_request_headers = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "record",
                fields = {
                  { header = { type = "string", required = true, custom_validator = validate_header_name } },
                  { value = { type = "string", required = true } },
                },
              },
            },
          },
          {
            array_unwrap_paths = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "string",
                custom_validator = validate_json_path,
              },
            },
          },
          {
            required_paths = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "string",
                custom_validator = validate_json_path,
              },
            },
          },
          {
            output_header_mappings = {
              type = "array",
              required = true,
              default = {},
              elements = {
                type = "record",
                fields = {
                  { header = { type = "string", required = true, custom_validator = validate_header_name } },
                  { source_path = { type = "string", required = true, custom_validator = validate_json_path } },
                  { json_encode = { type = "boolean", required = true, default = false } },
                },
              },
            },
          },
        },
        custom_validator = function(config)
          if config.graph_query == "" then
            return nil, "graph_query is required"
          end

          if #config.variable_mappings == 0 then
            return nil, "configure at least one variable_mappings entry"
          end

          if #config.output_header_mappings == 0 then
            return nil, "configure at least one output_header_mappings entry"
          end

          return true
        end,
      },
    },
  },
}
