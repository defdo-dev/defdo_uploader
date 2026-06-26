defmodule Defdo.S3Uploader.DefaultBackend do
  @moduledoc false
  @behaviour Defdo.S3Uploader.CredentialsBackend

  @impl true
  def put(_creds, _opts), do: {:error, :no_backend_configured}

  @impl true
  def get(_opts), do: :error

  @impl true
  def present?(_opts), do: false
end
