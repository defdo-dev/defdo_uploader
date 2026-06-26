defmodule Defdo.S3Uploader do
  @moduledoc """
  S3 operations, vault-backed credentials, and embeddable admin form.

  ## Architecture

  `defdo_s3_uploader` works at three levels depending on which optional
  dependencies are available:

  ### Level 1 — S3 only (no defdo_tenant, no vault)

      S3Client.upload_file(path, key, config)

  ### Level 2 — With defdo_tenant

      S3Client.upload_file(path, key, config, tenant_id: "tenant-123")
      S3Credentials.put(creds, tenant_id: "tenant-123")

  ### Level 3 — With defdo_tenant + defdo_vault + Phoenix LiveView

      render S3Credentials.Component, tenant_id: @tenant_id

  ## Quick start

  ```elixir
  # mix.exs
  {:defdo_s3_uploader, "~> 0.1", organization: "defdo"}
  ```
  """
end
