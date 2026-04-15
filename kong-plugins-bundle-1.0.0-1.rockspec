package = "kong-plugins-bundle"
version = "1.0.0-1"

source = {
  url = "git+https://github.com/Eaglessoft/kong-plugins.git",
}

description = {
  summary = "Bundle package for Eaglessoft Kong external plugins",
  detailed = [[
Monorepo bundle package that ships multiple Kong external plugins in a single
LuaRocks artifact. Installation is unified, but Kong plugin activation still
remains per-plugin via KONG_PLUGINS or KongPlugin resources.
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
    ["kong.plugins.edge-cors-policy.handler"] = "edge-cors-policy/kong/plugins/edge-cors-policy/handler.lua",
    ["kong.plugins.edge-cors-policy.schema"] = "edge-cors-policy/kong/plugins/edge-cors-policy/schema.lua",
    ["kong.plugins.edge-header-policy.handler"] = "edge-header-policy/kong/plugins/edge-header-policy/handler.lua",
    ["kong.plugins.edge-header-policy.schema"] = "edge-header-policy/kong/plugins/edge-header-policy/schema.lua",
    ["kong.plugins.graph-context-enricher.handler"] = "graph-context-enricher/kong/plugins/graph-context-enricher/handler.lua",
    ["kong.plugins.graph-context-enricher.schema"] = "graph-context-enricher/kong/plugins/graph-context-enricher/schema.lua",
    ["kong.plugins.jwt-auth-context.handler"] = "jwt-auth-context/kong/plugins/jwt-auth-context/handler.lua",
    ["kong.plugins.jwt-auth-context.schema"] = "jwt-auth-context/kong/plugins/jwt-auth-context/schema.lua",
  }
}
