# edge-cors-policy

`edge-cors-policy` is a Kong plugin that enforces CORS decisions at the gateway boundary instead of delegating them to upstream applications.

It validates the incoming `Origin`, evaluates preflight method and header requests, short-circuits preflight traffic, and emits deterministic CORS response headers.

## Installation

### Install this plugin only

```bash
cd edge-cors-policy
luarocks make
```

Or install a built rock:

```bash
luarocks install kong-plugin-edge-cors-policy-1.0.0-1.all.rock
```

Enable it in Kong:

```bash
export KONG_PLUGINS=bundled,edge-cors-policy
```

### Install through the bundle package

From the `external_plugins` directory:

```bash
luarocks make kong-plugins-bundle-1.0.0-1.rockspec
```

Then enable the plugin by name:

```bash
export KONG_PLUGINS=bundled,edge-cors-policy
```

## Infra Examples

- [KongPlugin](../infra/edge-cors-policy/kongplugin.yaml)
- [KongClusterPlugin](../infra/edge-cors-policy/kongclusterplugin.yaml)
- [Ingress](../infra/edge-cors-policy/ingress.yaml)
- [HTTPRoute](../infra/edge-cors-policy/httproute.yaml)

## Behavior

- Parses and validates the `Origin` header.
- Allows exact origins or host suffixes.
- Handles preflight requests in the plugin without proxying upstream.
- Rejects or silently denies disallowed origins depending on config.
- Extends `Vary` correctly for cache safety.

## Main Config Fields

- `allow_all_origins`
- `allowed_origins`
- `allowed_host_suffixes`
- `allow_methods`
- `allow_headers`
- `expose_headers`
- `allow_credentials`
- `max_age`
- `reject_disallowed_origins`
- `reject_status_code`
- `allow_private_network`

See [schema.lua](./kong/plugins/edge-cors-policy/schema.lua) for the exact schema and defaults.
