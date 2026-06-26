defmodule Defdo.Uploader.CredentialsBackend do
  @moduledoc """
  Behaviour for S3 credential storage backends.

  Implement this behaviour to plug in `defdo_vault`, `Cachex`,
  or a simple Agent for testing.
  """

  @type creds :: %{
          required(:access_key_id) => String.t(),
          required(:secret_access_key) => String.t(),
          optional(:bucket) => String.t(),
          optional(:region) => String.t(),
          optional(:endpoint) => String.t()
        }

  @type opts :: keyword()

  @callback put(creds(), opts()) :: :ok | {:error, term()}
  @callback get(opts()) :: {:ok, creds()} | :error | {:error, term()}
  @callback present?(opts()) :: boolean()
end
