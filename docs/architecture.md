# Edge Architecture — defdo_uploader ≥ 0.1.0

## Positioning

`defdo_uploader` is a **pluggable storage component** for the Defdo ecosystem.
It provides a unified API for file operations (upload, head, delete, public URL)
backed by swappable adapters (S3, HTTP, WebDAV, Google Drive, …) and optional
vault-backed credential storage.

```
  defdo_cms         defdo_notification_hub      defdo_theme_hub
       │                     │                        │
       └─────────┬───────────┴───────────┬────────────┘
                 │                       │
          ┌──────┴──────┐         ┌──────┴──────┐
          │  S3CredentialsForm  │  │  Client API  │
          │  (LiveComponent)    │  │  (raw calls)  │
          └──────┬──────┘         └──────┬──────┘
                 │                       │
          ┌──────┴───────────────────────┴──────┐
          │           defdo_uploader             │
          │                                      │
          │  ┌──────────┐  ┌──────────────────┐  │
          │  │ Adapter  │  │   Credentials    │  │
          │  │ S3 HTTP  │  │ Vault Cachex ... │  │
          │  └──────────┘  └──────────────────┘  │
          └──────────────────────────────────────┘
```

## Three Levels

`defdo_uploader` works at three levels depending on which optional dependencies
are available. Only `defdo_s3` and `req` are mandatory; `image` is required by `Defdo.Uploader.Storage`.

### Level 1 — Raw S3 (zero dependencies)

```elixir
# mix.exs — only this
{:defdo_uploader, "~> 0.3", organization: "defdo"}

# Usage
alias Defdo.Uploader.Adapters.S3

config = %{access_key_id: "AKI...", secret_access_key: "...", bucket: "my-bucket", region: "us-east-1"}

S3.upload_file("photo.jpg", "uploads/photo.jpg", config)
# {:ok, %{url: "https://my-bucket.s3.amazonaws.com/uploads/photo.jpg", ...}}

S3.head_object("uploads/photo.jpg", config)
# {:ok, %{content_length: 12345, content_type: "image/jpeg", etag: "abc123", ...}}

S3.delete_object("uploads/photo.jpg", config)
# :ok

S3.build_public_url("my-bucket", "uploads/photo.jpg", "https://my-endpoint.example.com")
# "https://my-endpoint.example.com/my-bucket/uploads/photo.jpg"
```

### Level 2 — With defdo_tenant (tenant-scoped)

```elixir
# mix.exs
{:defdo_uploader, "~> 0.3", organization: "defdo"},
{:defdo_tenant, "~> 0.15", organization: "defdo"}

# Usage — tenant_id in opts or from process context
# Keys are tenant-scoped by Defdo.Uploader.Key; the tenant comes from context.
Storage.put(:tenant_logo, bytes, config: config, id: "brand")

S3Credentials.put(
  %{access_key_id: "...", secret_access_key: "..."},
  tenant_id: "tenant-abc"
)

{:ok, creds} = S3Credentials.get(tenant_id: "tenant-abc")
```

### Level 3 — With defdo_vault + Phoenix LiveView (full stack)

```elixir
# mix.exs
{:defdo_uploader, "~> 0.3", organization: "defdo"},
{:defdo_tenant, "~> 0.15", organization: "defdo"},
{:defdo_vault, "~> 0.9", organization: "defdo"},
{:phoenix_live_view, "~> 1.0"}

# config.exs
config :defdo_uploader, :credentials_backend, Defdo.Uploader.VaultBackend

# Router
live_session :admin,
  on_mount: {Defdo.TenantPlug.LiveView, :default} do
  live "/admin/s3", AdminS3Live
end

# LiveView — embed the form component
def render(assigns) do
  ~H"""
  <.live_component
    module={Defdo.Uploader.CredentialsForm}
    id="s3-creds"
    tenant_id={@tenant_id}
    return_to={~p"/admin"}
  />
  """
end
```

## Adapter Behaviour

All adapters implement 4 callbacks:

```elixir
defmodule Defdo.Uploader.Adapter do
  @callback upload(source_path, object_key, config, opts) ::
              {:ok, upload_result()} | {:error, term()}

  @callback head(object_key, config, opts) ::
              {:ok, head_result()} | {:error, term()}

  @callback delete(object_key, config, opts) ::
              :ok | {:error, term()}

  @callback public_url(bucket, object_key, config, opts) :: String.t()
end
```

### Current adapters

| Adapter | Status | Notes |
|---------|--------|-------|
| `Adapters.S3` | ✅ | S3, R2, MinIO. Via `defdo_s3`. |
| `Adapters.HTTP` | ⬜ | Future: `PUT`, `HEAD`, `DELETE` to any HTTP endpoint |
| `Adapters.WebDAV` | ⬜ | Future: WebDAV protocol |
| `Adapters.GoogleDrive` | ⬜ | Future: Google Drive API |

### Creating a custom adapter

```elixir
defmodule MyApp.CustomAdapter do
  @behaviour Defdo.Uploader.Adapter

  @impl true
  def upload(source, key, config, _opts) do
    # Your upload logic
  end

  @impl true
  def head(key, config, _opts), do: {:ok, %{content_length: nil, ...}}

  @impl true
  def delete(key, config, _opts), do: :ok

  @impl true
  def public_url(bucket, key, config, _opts), do: "https://..."
end

# Use it: there is no global adapter setting; pass it per call.
Defdo.Uploader.Storage.put(:tenant_logo, bytes, config: config, id: "brand",
  adapter: MyApp.CustomAdapter)
```

## Credentials

Credentials are resolved through a pluggable backend. The default backend
returns errors (no storage configured). Enable `VaultBackend` for encrypted
per-tenant credential storage.

```elixir
# Behaviour
@callback put(creds, opts) :: :ok | {:error, term()}
@callback get(opts) :: {:ok, creds} | :error
@callback present?(opts) :: boolean()

# Usage
S3Credentials.put(%{access_key_id: "...", secret_access_key: "..."}, tenant_id: "t-1")
{:ok, creds} = S3Credentials.get(tenant_id: "t-1")
```

## Tenant Contract

Following the `defdo_wa` pattern, `tenant_id` is **opaque** inside the package.
The SDK never interprets it. Host apps provide it via opts or process context.

```elixir
# Explicit tenant — for system edges outside a request. When a context tenant
# is also set they must agree, or Key.base/2 returns {:error, :tenant_mismatch}.
Storage.put(:tenant_logo, bytes, config: config, id: "brand", tenant_id: "tenant-123")
S3Credentials.put(creds, tenant_id: "tenant-123")

# From process context — requires defdo_tenant
S3Credentials.put(creds)  # reads Defdo.Tenant.Context.tenant_id()

# Raw adapter — no tenant, no policy; the caller owns the key
S3.upload_file(path, key, config)
```

## Reactivity

When `defdo_tenant_boundary` is available, credential updates are broadcast
via PubSub so all connected admins see changes in real time:

```
User A saves creds
  → S3Credentials.put(creds)
    → vault: upsert
    → PubSub.broadcast("uploader:tenant:#{tenant_id}", {:credentials_updated})

User B (same tenant)
  → handle_info({:credentials_updated})
  → S3Credentials.get()
  → UI updates
```

## Dependency Map

```
defdo_uploader
  │
  ├── required
  │   ├── req ~> 0.5
  │   └── defdo_s3 ~> 0.2
  │
  └── optional (opt-in per level)
      ├── defdo_tenant ~> 0.15       → Level 2: tenant isolation
      ├── defdo_vault ~> 0.9         → Level 3: encrypted creds
      ├── defdo_tenant_boundary ~> 0.2 → Level 3: PubSub reactivity
      └── phoenix_live_view >= 1.0   → Level 3: embeddable form
```

## Quick Reference

| Do | Notes |
|----|-------|
| `S3.upload_file(path, key, config)` | Upload to S3 |
| `S3.head_object(key, config)` | Object metadata |
| `S3.delete_object(key, config)` | Delete object |
| `S3.build_public_url(bucket, key, endpoint)` | Build URL |
| `S3Credentials.put(creds, opts)` | Store credentials |
| `S3Credentials.get(opts)` | Retrieve credentials |
| `S3Credentials.present?(opts)` | Check if configured |
| `S3.validate_config(config)` | Validate config shape |
