# Kong External Plugins

This directory contains the external Kong plugins maintained in this repository, their individual `.rockspec` packages, a bundle `.rockspec`, and Kubernetes example manifests grouped by plugin.

## Layout

```text
external_plugins/
  README.md
  kong-plugins-bundle-1.0.0-1.rockspec
  edge-cors-policy/
  edge-header-policy/
  jwt-auth-context/
  graph-context-enricher/
  infra/
    edge-cors-policy/
    edge-header-policy/
    jwt-auth-context/
    graph-context-enricher/
```

## Plugins

- [edge-cors-policy](./edge-cors-policy/README.md)
- [edge-header-policy](./edge-header-policy/README.md)
- [jwt-auth-context](./jwt-auth-context/README.md)
- [graph-context-enricher](./graph-context-enricher/README.md)

## Installation Models

### Individual plugin package

Each plugin ships its own `.rockspec` file inside its plugin directory.

Examples:

- [edge-cors-policy rockspec](./edge-cors-policy/kong-plugin-edge-cors-policy-1.0.0-1.rockspec)
- [edge-header-policy rockspec](./edge-header-policy/kong-plugin-edge-header-policy-1.0.0-1.rockspec)
- [jwt-auth-context rockspec](./jwt-auth-context/kong-plugin-jwt-auth-context-1.0.0-1.rockspec)
- [graph-context-enricher rockspec](./graph-context-enricher/kong-plugin-graph-context-enricher-1.0.0-1.rockspec)

Install one plugin:

```bash
cd edge-cors-policy
luarocks make
```

Or from a built `.rock` artifact:

```bash
luarocks install kong-plugin-edge-cors-policy-1.0.0-1.all.rock
```

### Bundle package

The repository root of `external_plugins` also ships a bundle rockspec:

- [kong-plugins-bundle-1.0.0-1.rockspec](./kong-plugins-bundle-1.0.0-1.rockspec)

This installs multiple plugin modules through one LuaRocks package:

```bash
cd external_plugins
luarocks make kong-plugins-bundle-1.0.0-1.rockspec
```

Important: the bundle only changes packaging. Kong runtime activation is still per plugin name:

```bash
export KONG_PLUGINS=bundled,edge-cors-policy,edge-header-policy,jwt-auth-context,graph-context-enricher
```

## Kubernetes Examples

Infra examples are grouped by plugin under `infra/`.

- [edge-cors-policy examples](./infra/edge-cors-policy/)
- [edge-header-policy examples](./infra/edge-header-policy/)
- [jwt-auth-context examples](./infra/jwt-auth-context/)
- [graph-context-enricher examples](./infra/graph-context-enricher/)

Each folder contains examples for:

- `KongPlugin`
- `KongClusterPlugin`
- `Ingress`
- `HTTPRoute`

Use them as templates only. Adjust namespace, hosts, service names, and plugin config values for your environment.
