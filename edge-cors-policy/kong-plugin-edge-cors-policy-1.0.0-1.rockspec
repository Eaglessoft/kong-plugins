package = "kong-plugin-edge-cors-policy"
version = "1.0.0-1"
source = {
  url = "git+https://github.com/Eaglessoft/kong-plugins.git",
}

description = {
  summary = "Strict and maintainable edge CORS policy plugin for Kong Gateway",
  detailed = [[
Gateway-level CORS policy enforcement for Kong Gateway.
Validates Origin, preflight method/header combinations, and emits
deterministic CORS response headers without delegating the decision upstream.
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
    ["kong.plugins.edge-cors-policy.handler"] = "kong/plugins/edge-cors-policy/handler.lua",
    ["kong.plugins.edge-cors-policy.schema"] = "kong/plugins/edge-cors-policy/schema.lua",
  }
}
