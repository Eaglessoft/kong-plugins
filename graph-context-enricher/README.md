# graph-context-enricher

`graph-context-enricher` is a generic GraphQL-backed context enrichment plugin for Kong.

It reads selected request headers, builds GraphQL variables from them, calls a configured Graph endpoint, optionally enforces result policies, and writes selected response fields to upstream request headers.

## Installation

### Install this plugin only

```bash
cd graph-context-enricher
luarocks make
```

Or install a built rock:

```bash
luarocks install kong-plugin-graph-context-enricher-1.0.0-1.all.rock
```

Enable it in Kong:

```bash
export KONG_PLUGINS=bundled,graph-context-enricher
```

### Install through the bundle package

```bash
cd external_plugins
luarocks make kong-plugins-bundle-1.0.0-1.rockspec
export KONG_PLUGINS=bundled,graph-context-enricher
```

## Infra Examples

- [KongPlugin](../infra/graph-context-enricher/kongplugin.yaml)
- [KongClusterPlugin](../infra/graph-context-enricher/kongclusterplugin.yaml)
- [Ingress](../infra/graph-context-enricher/ingress.yaml)
- [HTTPRoute](../infra/graph-context-enricher/httproute.yaml)

## Behavior

- Builds GraphQL variables from request headers.
- Forwards selected request headers to the Graph backend.
- Adds optional static request headers for internal backend authorization.
- Calls the configured Graph endpoint with the configured query.
- Supports separate policies for:
  - upstream errors
  - missing data
  - multiple results
- Writes selected response values to upstream request headers.

## Main Config Fields

- `graph_url`
- `graph_query`
- `variable_mappings`
- `forward_headers`
- `static_request_headers`
- `array_unwrap_paths`
- `required_paths`
- `output_header_mappings`
- `on_upstream_error`
- `on_missing_data`
- `on_multiple_results`

See [schema.lua](./kong/plugins/graph-context-enricher/schema.lua) for the exact schema and defaults.

## Generic Example

```yaml
plugins:
  - name: graph-context-enricher
    config:
      graph_url: https://graph.example.com/v1/graphql
      graph_query: |
        query ResolveContext($tenant_id: String!, $user_id: String!) {
          tenant(where: { id: { _eq: $tenant_id } }) {
            id
            slug
          }
          user(where: { id: { _eq: $user_id } }) {
            id
            email
            roles
          }
        }
      on_upstream_error: reject
      on_missing_data: reject
      on_multiple_results: reject
      variable_mappings:
        - variable: tenant_id
          from_header: x-tenant-id
          required: true
        - variable: user_id
          from_header: x-auth-token-user-id
          required: true
      forward_headers:
        - authorization
      static_request_headers:
        - header: x-service-role
          value: context_reader
      array_unwrap_paths:
        - $.data.tenant
        - $.data.user
      required_paths:
        - $.data.tenant
        - $.data.user
      output_header_mappings:
        - header: X-Context-Tenant-Id
          source_path: $.data.tenant.id
        - header: X-Context-Tenant-Slug
          source_path: $.data.tenant.slug
        - header: X-Context-User-Id
          source_path: $.data.user.id
        - header: X-Context-User-Roles
          source_path: $.data.user.roles
          json_encode: true
```

## Notes

- This plugin does not extract user identity from JWTs by itself.
- It is typically chained after `jwt-auth-context`, which writes trusted identity headers such as `x-auth-token-user-id`.
- Output headers are cleared before being rewritten, which prevents client spoofing for owned headers.
