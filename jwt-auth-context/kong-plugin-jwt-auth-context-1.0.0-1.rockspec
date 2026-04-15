package = "kong-plugin-jwt-auth-context"
version = "1.0.0-1"
source = {
  url = "git+https://github.com/Eaglessoft/kong-plugins.git",
}

description = {
  summary = "JWT validation and claim-to-header context generation for Kong",
  detailed = [[
Gateway-level JWT validation and context propagation plugin for Kong Gateway.
Fetches JWKS, verifies token signatures and selected claims, then writes
trusted claim values into upstream request headers.
]],
  homepage = "https://github.com/Eaglessoft/kong-plugins",
  license = "Apache-2.0",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.jwt-auth-context.handler"] = "kong/plugins/jwt-auth-context/handler.lua",
    ["kong.plugins.jwt-auth-context.schema"] = "kong/plugins/jwt-auth-context/schema.lua",
  }
}
