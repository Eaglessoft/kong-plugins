"""Run focused plugin tests in Kong's supported LuaJIT runtime, without live credentials."""
import os
from pathlib import Path
import subprocess
import unittest


class JwtAuthContextTests(unittest.TestCase):
    def run_lua(self, entrypoint, arguments):
        root = Path(__file__).resolve().parents[1]
        image = os.environ.get("KONG_TEST_IMAGE", "kong:3.9.1")
        command = [
            "docker", "run", "--rm", "--network", "none",
            "--mount", f"type=bind,source={root},target=/workspace,readonly",
            "--workdir", "/workspace", "--entrypoint", entrypoint,
            image, *arguments,
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        print(result.stdout, end="")

    def test_plugin_behavior_and_schema(self):
        self.run_lua("/usr/local/openresty/luajit/bin/luajit", ["tests/jwt_auth_context_spec.lua"])

    def test_actual_kong_configuration_schema(self):
        script = r'''
local Schema = require "kong.db.schema"
local cjson = require "cjson"
local definition = dofile("jwt-auth-context/kong/plugins/jwt-auth-context/schema.lua")
local instance, err = Schema.new({ name = "auth-config-test", fields = { definition.fields[3] } })
assert(instance, tostring(err))
local function check(config, expected)
  config.jwks_url = "https://sso.example/certs"
  local data = instance:process_auto_fields({ config = config }, "insert")
  local ok, errors = instance:validate(data)
  assert((ok == true) == expected, cjson.encode(errors))
  return data.config
end
local defaults = check({}, true)
assert(defaults.client_credentials_enabled == false)
assert(defaults.client_id_header == "X-Client-Id")
assert(defaults.client_secret_header == "X-API-Key")
check({ client_credentials_enabled = true }, false)
check({ client_credentials_enabled = true, token_endpoint_url = ngx.null }, false)
check({ client_credentials_enabled = true, token_endpoint_url = "https://sso.example/token" }, true)
for _, url in ipairs({ "http://sso.example/token", "https://user:secret@sso.example/token", "https://sso.example/token#fragment" }) do
  check({ client_credentials_enabled = true, token_endpoint_url = url }, false)
end
for _, header in ipairs({ "Authorization", "Cookie", "X-Auth-Token-User-Id", "Transfer-Encoding", "invalid header", "X-API-Key" }) do
  check({ client_credentials_enabled = true, token_endpoint_url = "https://sso.example/token", client_id_header = header }, false)
end
print("Actual Kong configuration schema: defaults, valid exchange and 11 invalid configurations passed")
'''
        self.run_lua("/usr/local/openresty/bin/resty", ["-e", script])


if __name__ == "__main__":
    unittest.main()
