defmodule Defdo.Uploader do
  @moduledoc """
  Pluggable storage component for the Defdo ecosystem.

  ## Architecture

      defdo_uploader
      ├── Adapter (behaviour) → Adapters.S3, HTTP, WebDAV...
      ├── CredentialsBackend → VaultBackend, CachexBackend, DefaultBackend
      └── CredentialsForm → embeddable LiveComponent

  ## Quick start

  ```elixir
  # mix.exs
  {:defdo_uploader, "~> 0.1", organization: "defdo"}

  # config.exs — enable vault-backed credentials
  config :defdo_uploader, :credentials_backend, Defdo.Uploader.VaultBackend
  config :defdo_uploader, :otp_app, :my_app
  ```

  ## Usage

      alias Defdo.Uploader.Adapters.S3
      alias Defdo.Uploader.S3Credentials

      # Raw S3 operations
      S3.upload_file("photo.jpg", "uploads/photo.jpg", config)

      # With tenant isolation
      S3Credentials.put(creds, tenant_id: "tenant-123")
      {:ok, creds} = S3Credentials.get(tenant_id: "tenant-123")

  See `docs/architecture.md` for the full guide.
  """
end
