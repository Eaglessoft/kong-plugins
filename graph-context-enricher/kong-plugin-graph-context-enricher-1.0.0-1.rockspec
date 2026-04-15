package = "kong-plugin-graph-context-enricher"
version = "1.0.0-1"
source = {
  url = "git+https://github.com/Eaglessoft/kong-plugins.git",
}

description = {
  summary = "Graph-backed request context enrichment for Kong",
  detailed = [[
Gateway-level context enrichment plugin for Kong Gateway. Builds GraphQL variables
from request headers, calls a configured Graph backend, optionally validates
missing/multiple result policies, and writes selected response fields to upstream headers.
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
    ["kong.plugins.graph-context-enricher.handler"] = "kong/plugins/graph-context-enricher/handler.lua",
    ["kong.plugins.graph-context-enricher.schema"] = "kong/plugins/graph-context-enricher/schema.lua",
  }
}
