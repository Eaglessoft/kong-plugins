# edge-header-policy

`edge-header-policy` is a Kong plugin for request and response header hygiene at the gateway edge.

It removes spoofable internal request headers before proxying upstream and strips selected internal or noisy response headers before the final client response leaves Kong.

## Installation

### Install this plugin only

```bash
cd edge-header-policy
luarocks make
```

Or install a built rock:

```bash
luarocks install kong-plugin-edge-header-policy-1.0.0-1.all.rock
```

Enable it in Kong:

```bash
export KONG_PLUGINS=bundled,edge-header-policy
```

### Install through the bundle package

```bash
cd external_plugins
luarocks make kong-plugins-bundle-1.0.0-1.rockspec
export KONG_PLUGINS=bundled,edge-header-policy
```

## Infra Examples

- [KongPlugin](../infra/edge-header-policy/kongplugin.yaml)
- [KongClusterPlugin](../infra/edge-header-policy/kongclusterplugin.yaml)
- [Ingress](../infra/edge-header-policy/ingress.yaml)
- [HTTPRoute](../infra/edge-header-policy/httproute.yaml)

## Behavior

- Scans all request headers in `access`.
- Removes blocked exact headers and blocked prefixes unless explicitly allowlisted.
- Scans all response headers in `header_filter`.
- Removes internal, spoofable, or noisy response headers before the final response.
- Supports `append` and `override` modes for default exact and prefix rules.

## Main Config Fields

- `request_exact_mode`
- `request_prefix_mode`
- `response_exact_mode`
- `response_prefix_mode`
- `request_allow_headers`
- `request_allow_prefixes`
- `request_block_headers`
- `request_block_prefixes`
- `response_allow_headers`
- `response_allow_prefixes`
- `response_block_headers`
- `response_block_prefixes`

See [schema.lua](./kong/plugins/edge-header-policy/schema.lua) for the exact schema and defaults.
