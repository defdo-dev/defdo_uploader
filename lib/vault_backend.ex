defmodule Defdo.Uploader.VaultBackend do
  @moduledoc """
  defdo_vault-backed credentials backend.

  Stores S3 credentials encrypted in `vault_secrets`, keyed by
  `code: "s3"`, the embedding app's `otp_app`, and `env`.

  Requires `defdo_vault` as a dependency of the embedding app.

  ## Configuration

      config :defdo_uploader, :credentials_backend, Defdo.Uploader.VaultBackend
      config :defdo_uploader, :otp_app, :my_app

  ## Tenant

  `tenant_id` is resolved from opts or `Defdo.Tenant.Context`.
  When `defdo_tenant` is not available, `tenant_id` must be passed
  explicitly.
  """

  @behaviour Defdo.Uploader.CredentialsBackend

  @code "s3"
  @credential_keys %{
    "access_key_id" => :access_key_id,
    "secret_access_key" => :secret_access_key,
    "region" => :region,
    "bucket" => :bucket,
    "endpoint" => :endpoint
  }

  alias Defdo.Tenant.Context

  @impl true
  def put(creds, opts) when is_map(creds) do
    with {:ok, tenant_id} <- ensure_tenant(opts),
         :ok <- ensure_vault() do
      otp_app = otp_app(opts)
      env = env(opts)

      content = normalize_content(creds)

      vault_module().upsert_secret(
        %{
          code: @code,
          otp_app: otp_app,
          env: env,
          content: content,
          metadata: %{},
          tenant_id: tenant_id
        },
        tenant_id: tenant_id
      )
    end
  end

  @impl true
  def get(opts) do
    with {:ok, tenant_id} <- ensure_tenant(opts),
         :ok <- ensure_vault() do
      otp_app = otp_app(opts)
      env = env(opts)

      result = fetch_secret(tenant_id, otp_app, env)

      case result do
        %{content: content} ->
          {:ok, normalize_content(content)}

        _ ->
          :error
      end
    end
  end

  @impl true
  def present?(opts) do
    case get(opts) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp ensure_tenant(opts) do
    tenant_id = Keyword.get(opts, :tenant_id) || tenant_from_context()

    case tenant_id do
      id when is_binary(id) and id != "" -> {:ok, id}
      nil -> {:error, :tenant_required}
      _ -> {:ok, tenant_id}
    end
  end

  defp tenant_from_context do
    if Code.ensure_loaded?(Context) do
      Context.tenant_id()
    end
  end

  defp ensure_vault do
    if Code.ensure_loaded?(defdo_vault_module()) do
      :ok
    else
      {:error, :vault_not_available}
    end
  end

  defp otp_app(opts) do
    Keyword.get(opts, :otp_app) ||
      Application.get_env(:defdo_uploader, :otp_app) ||
      :defdo_uploader
  end

  defp env(opts) do
    Keyword.get(opts, :env) ||
      Application.get_env(:defdo_uploader, :env) ||
      to_string(Mix.env())
  end

  defp normalize_content(%{} = creds) do
    Map.new(creds, fn {k, v} -> {normalize_key(k), v} end)
  end

  defp normalize_content(other), do: other

  defp normalize_key(k) when is_atom(k) do
    Map.get(@credential_keys, Atom.to_string(k), k)
  end

  defp normalize_key(k) when is_binary(k), do: Map.get(@credential_keys, k, k)

  defp fetch_secret(tenant_id, otp_app, env) do
    attrs = %{
      "code" => @code,
      "otp_app" => to_string(otp_app),
      "env" => env
    }

    defdo_vault_module().get_secret(attrs)
    |> defdo_vault_module().one(tenant_id: tenant_id)
  end

  defp defdo_vault_module do
    Defdo.Vault
  end

  defp vault_module do
    Defdo.Vault.SDK
  end
end
