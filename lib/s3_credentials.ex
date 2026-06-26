defmodule Defdo.S3Uploader.S3Credentials do
  @moduledoc """
  Vault-backed S3 credential storage with optional tenant isolation.

  When `defdo_tenant` is available and `tenant_id` is omitted, reads
  from `Defdo.Tenant.Context.tenant_id()`.  Otherwise `tenant_id` must
  be passed explicitly via opts.

  ## Examples

      # With defdo_tenant in process context
      S3Credentials.put(%{access_key_id: "...", secret_access_key: "..."})

      # Explicit tenant
      S3Credentials.put(creds, tenant_id: "tenant-123")
      S3Credentials.get(tenant_id: "tenant-123")

      # Without defdo_tenant (standalone test)
      S3Credentials.put(creds, tenant_id: "default")
  """

  @type creds :: %{
          required(:access_key_id) => String.t(),
          required(:secret_access_key) => String.t(),
          optional(:bucket) => String.t(),
          optional(:region) => String.t(),
          optional(:endpoint) => String.t()
        }

  def put(creds, opts \\ [])
  def put(creds, opts) when is_map(creds), do: backend().put(creds, opts)

  def get(opts \\ []), do: backend().get(opts)

  def present?(opts \\ []), do: backend().present?(opts)

  defp backend do
    Application.get_env(:defdo_s3_uploader, :credentials_backend, DefaultBackend)
  end
end
