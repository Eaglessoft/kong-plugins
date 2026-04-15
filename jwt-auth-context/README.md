# jwt-auth-context

`jwt-auth-context` validates JWTs, applies selected claim checks, and writes trusted claim values to upstream request headers.

It is intended to run before plugins that depend on authenticated user context, such as `graph-context-enricher`.

## Installation

### Install this plugin only

```bash
cd jwt-auth-context
luarocks make
```

Or install a built rock:

```bash
luarocks install kong-plugin-jwt-auth-context-1.0.0-1.all.rock
```

Enable it in Kong:

```bash
export KONG_PLUGINS=bundled,jwt-auth-context
```

### Install through the bundle package

```bash
cd external_plugins
luarocks make kong-plugins-bundle-1.0.0-1.rockspec
export KONG_PLUGINS=bundled,jwt-auth-context
```

## Infra Examples

- [KongPlugin](../infra/jwt-auth-context/kongplugin.yaml)
- [KongClusterPlugin](../infra/jwt-auth-context/kongclusterplugin.yaml)
- [Ingress](../infra/jwt-auth-context/ingress.yaml)
- [HTTPRoute](../infra/jwt-auth-context/httproute.yaml)

## Behavior

- Extracts the token from `Authorization`, cookie, or query based on config order.
- Fetches and caches JWKS from the configured endpoint.
- Verifies signature, expiration, not-before, issuer, and audience.
- Optionally enforces `email_verified` and a required role.
- Clears the headers it owns and then writes trusted claim values.
- Supports `reject`, `pass`, and redirect flows depending on the failure mode.

## Main Config Fields

- `jwks_url`
- `jwks_cache_ttl_seconds`
- `ssl_verify`
- `expected_issuer`
- `expected_audience`
- `require_email_verified`
- `required_role`
- `on_missing_token`
- `on_invalid_token`
- `browser_redirect_url`
- `browser_redirect_only`
- `token_sources`
- `cookie_name`
- `query_param_name`
- `custom_header_mappings`

See [schema.lua](./kong/plugins/jwt-auth-context/schema.lua) for the exact schema and defaults.
