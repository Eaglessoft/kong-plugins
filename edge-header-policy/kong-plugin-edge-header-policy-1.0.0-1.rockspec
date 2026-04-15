package = "kong-plugin-edge-header-policy"
version = "1.0.0-1"
source = {
  url = "git+https://github.com/Eaglessoft/kong-plugins.git",
}

description = {
  summary = "Gateway boundary header hygiene and spoofing protection for Kong",
  detailed = [[
Gateway-level request and response header hygiene enforcement for Kong Gateway.
Strips spoofable internal request headers before upstream forwarding and removes
selected internal or noisy response headers before the final client response.
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
    ["kong.plugins.edge-header-policy.handler"] = "kong/plugins/edge-header-policy/handler.lua",
    ["kong.plugins.edge-header-policy.schema"] = "kong/plugins/edge-header-policy/schema.lua",
  }
}
