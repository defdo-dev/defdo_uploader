defmodule Defdo.Uploader.Adapter do
  @moduledoc """
  Behaviour for upload/storage adapters.

  Implement this behaviour to add S3, HTTP, WebDAV, Google Drive, or
  any custom storage backend.

  ## Required callbacks

    * `upload/4` — store a file and return metadata
    * `head/3`   — retrieve object metadata
    * `delete/3` — remove an object
    * `public_url/3` — build the public-facing URL
  """

  @type config :: map()
  @type opts :: keyword()
  @type upload_result :: %{
          url: String.t(),
          object_key: String.t(),
          bucket: String.t() | nil,
          endpoint: String.t() | nil
        }
  @type head_result :: %{
          content_length: integer() | nil,
          content_type: String.t() | nil,
          etag: String.t() | nil,
          last_modified: String.t() | nil
        }

  @callback upload(String.t(), String.t(), config(), opts()) ::
              {:ok, upload_result()} | {:error, term()}

  @callback head(String.t(), config(), opts()) ::
              {:ok, head_result()} | {:error, term()}

  @callback delete(String.t(), config(), opts()) :: :ok | {:error, term()}

  @callback public_url(String.t(), String.t(), config(), opts()) :: String.t()
end
