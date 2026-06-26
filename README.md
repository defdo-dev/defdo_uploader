# defdo_uploader

Pluggable storage component for the Defdo ecosystem.

Unified API for file operations (upload, head, delete, public URL) backed by
swappable adapters and optional vault-backed credential storage.

## Features

- **Adapter behaviour** — `Defdo.Uploader.Adapter` with `upload/4`, `head/3`,
  `delete/3`, `public_url/3`
- **S3/R2/MinIO** — `Defdo.Uploader.Adapters.S3` via `req_s3`
- **Vault-backed credentials** — `Defdo.Uploader.VaultBackend` stores secrets
  encrypted in `defdo_vault`
- **Embeddable admin form** — `Defdo.Uploader.CredentialsForm` LiveComponent
- **Tenant-aware** — optional `defdo_tenant` integration, tenant-scoped
  credentials

## Installation

```elixir
def deps do
  [
    {:defdo_uploader, "~> 0.1", organization: "defdo"}
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
