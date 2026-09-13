# defdo_uploader

Pluggable storage component for the Defdo ecosystem.

Unified API for file operations (upload, head, delete, public URL) backed by
swappable adapters and optional vault-backed credential storage.

## Features

- **Policy storage** — `Defdo.Uploader.Storage` admits, re-encodes and stores
  uploads by *kind*: tenant-scoped versioned keys, public or presigned
  delivery, WebP plus a PNG/JPEG fallback, metadata stripped
- **Adapter behaviour** — `Defdo.Uploader.Adapter` with `upload/4`, `head/3`,
  `delete/3`, `public_url/4`, and optional `put_object/5`, `get_object/2`,
  `presign_get/3`
- **S3/R2/MinIO** — `Defdo.Uploader.Adapters.S3` via `defdo_s3`
- **Vault-backed credentials** — `Defdo.Uploader.VaultBackend` stores secrets
  encrypted in `defdo_vault`
- **Embeddable admin form** — `Defdo.Uploader.CredentialsForm` LiveComponent
- **Tenant-aware** — optional `defdo_tenant` integration, tenant-scoped
  credentials

## Installation

```elixir
def deps do
  [
    {:defdo_uploader, "~> 0.3", organization: "defdo"},
    # Required by Defdo.Uploader.Storage for re-encoding
    {:image, "~> 0.72"}
  ]
end
```

## Quick start

```elixir
alias Defdo.Uploader.Adapters.S3

config = %{
  access_key_id: "AKIA...",
  secret_access_key: "...",
  bucket: "my-bucket",
  region: "us-east-1"
}

# Upload a file
S3.upload_file("/tmp/photo.png", "assets/photo.png", config)
# => {:ok, %{url: "https://...", object_key: "assets/photo.png", ...}}

# Check if object exists
S3.head_object("assets/photo.png", config)
# => {:ok, %{content_length: 2048, content_type: "image/png", ...}}

# Delete
S3.delete_object("assets/photo.png", config)
# => :ok

# Public URL
S3.build_public_url("my-bucket", "assets/photo.png", nil)
# => "https://my-bucket.s3.amazonaws.com/assets/photo.png"
```

## Policy storage

```elixir
alias Defdo.Uploader.Storage

config = %{
  access_key_id: "...",
  secret_access_key: "...",
  bucket: "assets",
  region: "auto",
  endpoint: "https://<account>.r2.cloudflarestorage.com",
  # Serves public kinds. An S3 API endpoint does not serve anonymous reads.
  public_base_url: "https://assets.example.com"
}

# The tenant comes from Defdo.Tenant.Context; pass :tenant_id only at system edges.
{:ok, stored} = Storage.put(:user_picture, upload_bytes, config: config, id: user.id)
# stored.variants => display.webp + fallback.jpg under
#   tenants/<tenant>/users/<id>/user_picture/<version>/

# Persist stored.variants' keys, never URLs.
variant = Storage.negotiate(stored.variants, get_req_header(conn, "accept") |> List.first())
{:ok, url} = Storage.url(:user_picture, variant.key, config: config)  # presigned, 5 min

:ok = Storage.delete(stored, config: config)
```

| Kind | Visibility | Variants |
|---|---|---|
| `:tenant_logo` | public | WebP 1024 + PNG 1024 (SVG rasterised) |
| `:tenant_background` | public | WebP 2560 + JPEG 2560 |
| `:user_picture` | private | WebP 512 + JPEG 512, square crop, no SVG |
| `:platform_icon` | public | PNG only — iOS, apple-touch, Play Store and favicons need PNG |

Every variant is re-encoded from pixels, which discards EXIF (including GPS),
appended bytes and polyglot payloads. The type is sniffed from the bytes, never
trusted from the filename. Override or add kinds with
`config :defdo_uploader, :kinds, %{...}` — see `Defdo.Uploader.Kind`.

## Credentials form

Embed the admin component in any LiveView:

```heex
<.live_component
  module={Defdo.Uploader.CredentialsForm}
  id="s3-creds"
  tenant_id={@tenant_id}
/>
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full edge architecture
guide with deployment levels, adapter pattern, and tenant contract.

## License

Apache-2.0
