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
luarocks install kong-plugin-jwt-auth-context-1.1.0-1.all.rock
```

Enable it in Kong:

```bash
export KONG_PLUGINS=bundled,jwt-auth-context
```

### Install through the bundle package

```bash
cd external_plugins
luarocks make kong-plugins-bundle-1.1.0-1.rockspec
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
- Optionally exchanges client-ID/secret headers for a token before applying the same JWT checks.

## Client Credentials

Client credentials are disabled by default. Enable them on selected routes:

```yaml
config:
  jwks_url: https://id.example.com/realms/main/protocol/openid-connect/certs
  expected_issuer: https://id.example.com/realms/main
  expected_audience: gateway
  client_credentials_enabled: true
  token_endpoint_url: https://id.example.com/realms/main/protocol/openid-connect/token
  client_id_header: X-Client-Id
  client_secret_header: X-API-Key
```

Clients can keep sending `Authorization: Bearer <access-token>`, or send:

```http
X-Client-Id: <integration-client-id>
X-API-Key: <integration-client-secret>
```

The plugin POSTs `grant_type=client_credentials`, `client_id`, and `client_secret`
as URL-encoded form fields to the configured HTTPS token endpoint. Configure the
Keycloak client with client authentication and service accounts enabled. No SSO
admin credentials or shared client secret belong in the plugin configuration.
The realm is already part of the endpoint/issuer URLs; discovery is not required.

Keycloak must issue a Bearer access token satisfying the configured issuer,
audience, email-verification, role, and custom-claim requirements. Configure the
service account and audience mappings accordingly; enabling this flow does not
relax JWT checks. The verified token supplies the same trusted claim headers as
an incoming JWT. The plugin also sets upstream `Authorization: Bearer <token>`
for downstream plugins such as `graph-context-enricher`, and removes both client
credential headers before proxying. Request bodies and business headers are unchanged.

Only one authentication method is allowed. Mixing a configured JWT source with
client credentials returns `400 MIXED_CREDENTIALS`; invalid, missing, empty, or
duplicate client credential values return `401 INVALID_CLIENT_CREDENTIALS`.
An invalid JWT never falls back to client credentials. With neither method supplied,
the existing `on_missing_token` policy still applies, including `pass` when explicitly
configured; use `reject` for routes requiring authentication.

Invalid client credentials return 401. A token-endpoint connection/timeout error,
redirect, server failure, or malformed token response returns `502 TOKEN_ENDPOINT_FAILED`.
The plugin reuses the configured connect/send/read timeouts and `ssl_verify` setting.
Keep TLS verification enabled in deployed environments. It does not follow token
endpoint redirects, retry token requests, or cache issued tokens. Each credential
request therefore requires an available token endpoint and adds a token request.
Credential values, issued tokens and raw provider error bodies are not logged or
returned by the exchange flow. Failed validation of an exchanged token returns an
authentication error instead of triggering a browser redirect.

Company membership and application permissions still belong to downstream
enrichment/services. Client-secret rotation prevents future token issuance with
that secret; already issued JWTs remain subject to their expiry and downstream
authorization checks.

Run the focused tests with Python and Docker:

```bash
python tests/test_jwt_auth_context.py
```

The runner uses Kong 3.9.4's LuaJIT with deterministic HTTP/JWT/Kong doubles and
no network access inside the test container. It verifies plugin decisions and
schema rules, not the configuration of a live Keycloak realm.

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
- `client_credentials_enabled` (default `false`)
- `token_endpoint_url` (HTTPS; required when client credentials are enabled)
- `client_id_header` (default `X-Client-Id`)
- `client_secret_header` (default `X-API-Key`)
- `custom_header_mappings`

See [schema.lua](./kong/plugins/jwt-auth-context/schema.lua) for the exact schema and defaults.
