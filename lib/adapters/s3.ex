defmodule Defdo.Uploader.Adapters.S3 do
  @moduledoc """
  S3/R2/MinIO adapter using defdo_s3.

  Implements `Defdo.Uploader.Adapter` for S3-compatible storage.
  """
  @behaviour Defdo.Uploader.Adapter

  require Logger
  alias Defdo.S3
  alias Req.Response

  @type creds :: %{
          required(:access_key_id) => String.t(),
          required(:secret_access_key) => String.t(),
          required(:bucket) => String.t(),
          optional(:region) => String.t(),
          optional(:endpoint) => String.t()
        }

  @type config :: %{
          required(:access_key_id) => String.t(),
          required(:secret_access_key) => String.t(),
          required(:bucket) => String.t(),
          required(:region) => String.t(),
          optional(:endpoint) => String.t()
        }

  @spec upload_file(String.t(), String.t(), config()) ::
          {:ok,
           %{
             url: String.t(),
             object_key: String.t(),
             bucket: String.t(),
             endpoint: String.t() | nil
           }}
          | {:error, term()}
  def upload_file(local_path, object_key, config)
      when is_binary(local_path) and is_binary(object_key) and is_map(config) do
    with :ok <- validate_config(config),
         true <- File.exists?(local_path) || {:error, :file_not_found},
         {bucket, _prefix} <- bucket_and_prefix(config.bucket),
         {:ok, client} <- client(config),
         {:ok, body} <- File.read(local_path),
         {:ok, response} <-
           Req.put(
             client,
             url: "s3://#{bucket}/#{object_key}",
             body: body,
             headers: content_type_header(local_path)
           ),
         # Req returns {:ok, response} for EVERY status, 403 included. Without
         # this check a rejected overwrite of an existing object fell through
         # to head_object, found the OLD object, and reported success with
         # stale metadata.
         :ok <- ensure_success(response),
         {:ok, head} <- head_object(object_key, config) do
      {:ok,
       %{
         bucket: bucket,
         content_length: head.content_length,
         content_type: head.content_type,
         etag: head.etag || first_header(response, "etag"),
         endpoint: normalize_endpoint(config[:endpoint]),
         object_key: object_key,
         url: build_public_url(bucket, object_key, config[:endpoint])
       }}
    else
      false -> {:error, :file_not_found}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @doc """
  Stores `body` at `object_key` with an explicit content type.

  Unlike `upload_file/3` the content type is never guessed from a filename:
  policy-managed uploads have already sniffed it from the bytes.

  Options:

    * `:cache_control` — sent as `Cache-Control` and stored on the object
  """
  @spec put_object(String.t(), binary(), String.t(), config(), keyword()) ::
          :ok | {:error, term()}
  @impl Defdo.Uploader.Adapter
  def put_object(object_key, body, content_type, config, opts \\ [])
      when is_binary(object_key) and object_key != "" and is_binary(body) and
             is_binary(content_type) and is_map(config) do
    headers =
      [{"content-type", content_type}]
      |> maybe_header("cache-control", opts[:cache_control])

    with :ok <- validate_config(config),
         {bucket, _prefix} <- bucket_and_prefix(config.bucket),
         {:ok, client} <- client(config),
         {:ok, response} <-
           Req.put(client, url: "s3://#{bucket}/#{object_key}", body: body, headers: headers) do
      ensure_success(response)
    end
  end

  @doc """
  Reads an object. A missing object is `{:error, :not_found}`.
  """
  @spec get_object(String.t(), config()) ::
          {:ok, %{body: binary(), content_type: String.t() | nil}} | {:error, term()}
  @impl Defdo.Uploader.Adapter
  def get_object(object_key, config)
      when is_binary(object_key) and object_key != "" and is_map(config) do
    with :ok <- validate_config(config),
         {bucket, _prefix} <- bucket_and_prefix(config.bucket),
         {:ok, client} <- client(config),
         # `decode_body: false` keeps an image, or a JSON object, as the raw
         # bytes that were stored.
         {:ok, response} <-
           Req.get(client, url: "s3://#{bucket}/#{object_key}", decode_body: false),
         :ok <- normalize_head_status(response.status) do
      {:ok, %{body: response.body, content_type: first_header(response, "content-type")}}
    end
  end

  def get_object(_object_key, _config), do: {:error, :invalid_object_key}

  @doc """
  A time-limited GET URL for a private object.

  Signing happens locally; no request is made. `expires` is in seconds.
  """
  @spec presign_get(String.t(), config(), pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  @impl Defdo.Uploader.Adapter
  def presign_get(object_key, config, expires \\ 300)
      when is_binary(object_key) and object_key != "" and is_map(config) and
             is_integer(expires) and expires > 0 do
    with :ok <- validate_config(config),
         {bucket, _prefix} <- bucket_and_prefix(config.bucket) do
      options =
        [
          bucket: bucket,
          key: object_key,
          access_key_id: config.access_key_id,
          secret_access_key: config.secret_access_key,
          region: config.region,
          expires: expires
        ]
        |> maybe_put_kv(:endpoint_url, normalize_endpoint(config[:endpoint]))

      {:ok, S3.presign_url(options)}
    end
  end

  @spec delete_object(String.t(), config()) :: :ok | {:error, term()}
  def delete_object(object_key, config)
      when is_binary(object_key) and object_key != "" and is_map(config) do
    with :ok <- validate_config(config),
         {bucket, _prefix} <- bucket_and_prefix(config.bucket),
         {:ok, client} <- client(config),
         {:ok, response} <- Req.delete(client, url: "s3://#{bucket}/#{object_key}"),
         # A 403 used to come back as :ok, so callers deleted their database
         # row and orphaned the object. A missing object is already the
         # desired end state, so 404 stays :ok and deletes remain idempotent.
         :ok <- ensure_deleted(response) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  def delete_object(_object_key, _config), do: :ok

  @spec head_object(String.t(), config()) ::
          {:ok,
           %{
             content_length: integer() | nil,
             content_type: String.t() | nil,
             etag: String.t() | nil,
             last_modified: String.t() | nil
           }}
          | {:error, term()}
  def head_object(object_key, config)
      when is_binary(object_key) and object_key != "" and is_map(config) do
    with :ok <- validate_config(config),
         {bucket, _prefix} <- bucket_and_prefix(config.bucket),
         {:ok, client} <- client(config),
         {:ok, response} <- Req.head(client, url: "s3://#{bucket}/#{object_key}"),
         :ok <- normalize_head_status(response.status) do
      {:ok,
       %{
         content_length: parse_integer_header(response, "content-length"),
         content_type: first_header(response, "content-type"),
         etag: first_header(response, "etag"),
         last_modified: first_header(response, "last-modified")
       }}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  def head_object(_object_key, _config), do: {:error, :invalid_object_key}

  @spec validate_config(map()) :: :ok | {:error, term()}
  def validate_config(%{
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        bucket: bucket,
        region: region
      })
      when is_binary(access_key_id) and access_key_id != "" and
             is_binary(secret_access_key) and secret_access_key != "" and
             is_binary(bucket) and bucket != "" and is_binary(region) and region != "" do
    :ok
  end

  def validate_config(_config), do: {:error, :missing_credentials}

  def build_public_url(bucket, object_key, endpoint)
      when is_binary(bucket) and is_binary(object_key) do
    case normalize_endpoint(endpoint) do
      nil -> "https://#{bucket}.s3.amazonaws.com/#{object_key}"
      normalized_endpoint -> normalized_endpoint <> "/" <> bucket <> "/" <> object_key
    end
  end

  @doc false
  def bucket_and_prefix(bucket) when is_binary(bucket) do
    case String.split(bucket, "/", parts: 2) do
      [b] -> {b, nil}
      [b, prefix] -> {b, prefix}
    end
  end

  def bucket_and_prefix(_), do: {nil, nil}

  @doc false
  def upload_one(client, bucket, key, url) do
    with {:ok, body, content_type} <- fetch_body(url),
         {:ok, response} <-
           Req.put(client,
             url: "s3://#{bucket}/#{key}",
             body: body,
             headers: content_type_value_header(content_type)
           ),
         :ok <- ensure_success(response) do
      {:ok, key}
    else
      {:error, reason} -> {:error, {key, reason}}
      other -> {:error, {key, other}}
    end
  end

  @doc """
  Normalize a settings/content map into an S3-compatible configuration.

  ## Example

      iex> S3Client.normalize_settings(%{"access_key_id" => "AKI...", "bucket" => "my-bucket"})
      %{access_key_id: "AKI...", bucket: "my-bucket", mode: "s3", ...}

  """
  def normalize_settings(%{} = content) do
    mode = normalize_string(Map.get(content, "mode", Map.get(content, :mode, "local")), "local")

    provider =
      normalize_string(Map.get(content, "provider", Map.get(content, :provider, "aws")), "aws")

    region_default = if provider == "cloudflare_r2", do: "auto", else: "us-east-1"

    %{
      access_key_id: normalize_string(content[:access_key_id] || content["access_key_id"], nil),
      bucket: normalize_string(content[:bucket] || content["bucket"], nil),
      endpoint: normalize_string(content[:endpoint] || content["endpoint"], nil),
      mode: mode,
      provider: provider,
      region: normalize_string(content[:region] || content["region"], region_default),
      secret_access_key:
        normalize_string(content[:secret_access_key] || content["secret_access_key"], nil),
      s3_uploader: content[:s3_uploader] || content["s3_uploader"]
    }
  end

  def normalize_settings(_content),
    do: %{mode: "local", provider: "aws", region: "us-east-1", s3_uploader: nil}

  @doc false
  def normalize_string(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      normalized -> normalized
    end
  end

  def normalize_string(nil, default), do: default
  def normalize_string(value, _default), do: to_string(value)

  # ── Private helpers ──────────────────────────────────────────────────

  defp fetch_body(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme in ["http", "https"] ->
        case Req.get(url, redirect: true) do
          {:ok, %{status: status, body: body, headers: headers}} when status in 200..299 ->
            {:ok, body, extract_content_type(headers)}

          {:ok, %{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      uri.scheme == "file" ->
        path = URI.decode(uri.path || "")
        read_local(path)

      File.exists?(url) ->
        read_local(url)

      true ->
        {:error, {:invalid_url, url}}
    end
  end

  defp fetch_body(other), do: {:error, {:invalid_url, other}}

  defp extract_content_type(headers) do
    headers
    |> Enum.find_value(fn
      {"content-type", ct} -> ct
      {"Content-Type", ct} -> ct
      _ -> nil
    end)
  end

  defp content_type_value_header(nil), do: []
  defp content_type_value_header(ct), do: [{"content-type", ct}]

  @doc false
  def client(creds) do
    sigv4 =
      []
      |> maybe_put_kv(:access_key_id, creds[:access_key_id])
      |> maybe_put_kv(:secret_access_key, creds[:secret_access_key])
      |> maybe_put_kv(:region, creds[:region] || System.get_env("AWS_REGION") || "us-east-1")

    opts =
      [aws_sigv4: sigv4]
      |> maybe_put_endpoint(creds[:endpoint])

    try do
      # `:req_options` is merged into the base request. Its main use is
      # `plug: {Req.Test, name}`, so the adapter can be exercised against a
      # stub without a network — this module had no tests at all before.
      {:ok, S3.attach(Req.new(creds[:req_options] || []), opts)}
    rescue
      error -> {:error, error}
    end
  end

  defp maybe_put_endpoint(opts, nil), do: opts
  defp maybe_put_endpoint(opts, endpoint), do: Keyword.put(opts, :aws_endpoint_url_s3, endpoint)

  defp maybe_put_kv(opts, _key, nil), do: opts
  defp maybe_put_kv(opts, key, value), do: Keyword.put(opts, key, value)

  defp read_local(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body, MIME.from_path(path)}
      other -> other
    end
  end

  defp normalize_endpoint(endpoint) when is_binary(endpoint) do
    endpoint
    |> String.trim()
    |> String.trim_trailing("/")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_endpoint(_endpoint), do: nil

  defp content_type_header(path) do
    case MIME.from_path(path) do
      nil -> []
      content_type -> [{"content-type", content_type}]
    end
  end

  defp maybe_header(headers, _name, nil), do: headers
  defp maybe_header(headers, name, value), do: headers ++ [{name, value}]

  defp ensure_success(%Response{status: status}) when status in 200..299, do: :ok
  defp ensure_success(%Response{status: status}), do: {:error, {:http_status, status}}

  defp ensure_deleted(%Response{status: 404}), do: :ok
  defp ensure_deleted(response), do: ensure_success(response)

  defp normalize_head_status(status) when status in 200..299, do: :ok
  defp normalize_head_status(404), do: {:error, :not_found}
  defp normalize_head_status(status), do: {:error, {:http_status, status}}

  defp first_header(%Response{} = response, name) when is_binary(name) do
    case Response.get_header(response, name) do
      [value | _rest] -> value
      _other -> nil
    end
  end

  defp parse_integer_header(%Response{} = response, name) when is_binary(name) do
    response
    |> first_header(name)
    |> case do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {parsed, _rest} -> parsed
          :error -> nil
        end
    end
  end

  # ── Adapter callbacks (delegating to existing public API) ──────────

  @impl Defdo.Uploader.Adapter
  def upload(source, key, config, _opts), do: upload_file(source, key, config)

  @impl Defdo.Uploader.Adapter
  def head(key, config, _opts), do: head_object(key, config)

  @impl Defdo.Uploader.Adapter
  def delete(key, config, _opts), do: delete_object(key, config)

  @impl Defdo.Uploader.Adapter
  def public_url(bucket, key, config, _opts), do: build_public_url(bucket, key, config[:endpoint])
end
