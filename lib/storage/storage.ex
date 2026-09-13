defmodule Defdo.Uploader.Storage do
  @moduledoc """
  Policy-driven storage for uploaded assets.

  `put/3` runs an upload through its kind's policy end to end:

    1. `Defdo.Uploader.Guard` admits it by size and by the type sniffed from
       its bytes.
    2. `Defdo.Uploader.ImagePipeline` re-encodes it into the kind's variants.
    3. `Defdo.Uploader.Key` places every variant under a tenant-scoped,
       versioned key.
    4. The adapter stores each variant with the kind's `Cache-Control`.

  If any variant fails to store, the variants already written are deleted, so
  a failed upload never leaves half of an asset behind.

  ## Reading

  `url/3` returns a public URL for a public kind and a short-lived presigned
  URL for a private one. Store **keys**, not URLs: a presigned URL expires,
  and a public URL changes whenever the public base URL does.

  ## Configuration

  The `config` map is the adapter configuration (credentials, bucket, region,
  endpoint) plus:

    * `:public_base_url` — the origin that serves public objects, e.g. a CDN
      or an R2 custom domain. Recommended: an S3 API endpoint such as
      `https://<account>.r2.cloudflarestorage.com` does not serve anonymous
      reads, so without it public URLs fall back to a path-style API URL
      that only works on buckets with public API access.
  """

  alias Defdo.Uploader.Adapters.S3
  alias Defdo.Uploader.{Guard, ImagePipeline, Key, Kind}

  @type stored_variant :: %{
          name: String.t(),
          key: String.t(),
          format: :webp | :png | :jpeg,
          content_type: String.t(),
          bytes: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer()
        }

  @type stored :: %{
          kind: atom(),
          base_key: String.t(),
          source_type: String.t(),
          variants: [stored_variant()]
        }

  @default_expires 300

  @doc """
  Admits, renders and stores `binary` as an asset of `kind`.

  Options:

    * `:config` (required) — see the moduledoc
    * `:id` (required), `:version`, `:tenant_id`, `:key_prefix` — see
      `Defdo.Uploader.Key.base/2`
    * `:adapter` — defaults to `Defdo.Uploader.Adapters.S3`
  """
  @spec put(atom() | Kind.t(), binary(), keyword()) :: {:ok, stored()} | {:error, term()}
  def put(kind, binary, opts) when is_binary(binary) do
    with {:ok, kind} <- Kind.fetch(kind),
         {:ok, config} <- fetch_config(opts),
         {:ok, source_type} <- Guard.admit(kind, binary),
         {:ok, base_key} <- Key.base(kind, opts),
         {:ok, rendered} <- ImagePipeline.render(kind, binary),
         {:ok, variants} <- store_all(kind, base_key, rendered, config, adapter(opts)) do
      {:ok, %{kind: kind.name, base_key: base_key, source_type: source_type, variants: variants}}
    end
  end

  @doc """
  A URL for `key`: public for a public kind, presigned for a private one.

  Options:

    * `:config` (required)
    * `:expires` — seconds a presigned URL stays valid, default #{@default_expires}
    * `:adapter`
  """
  @spec url(atom() | Kind.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def url(kind, key, opts) when is_binary(key) do
    with {:ok, kind} <- Kind.fetch(kind),
         {:ok, config} <- fetch_config(opts) do
      if Kind.public?(kind) do
        {:ok, public_url(key, config, adapter(opts))}
      else
        adapter(opts).presign_get(key, config, Keyword.get(opts, :expires, @default_expires))
      end
    end
  end

  @doc """
  Deletes every variant of a stored asset.

  Deletion is idempotent — an already-missing variant is not an error — and
  every key is attempted even when one fails, so the error lists exactly the
  objects that still exist.
  """
  @spec delete(stored() | [String.t()], keyword()) ::
          :ok | {:error, {:not_deleted, [{String.t(), term()}]}}
  def delete(%{variants: variants}, opts), do: delete(Enum.map(variants, & &1.key), opts)

  def delete(keys, opts) when is_list(keys) do
    with {:ok, config} <- fetch_config(opts) do
      adapter = adapter(opts)

      keys
      |> Enum.map(fn key -> {key, adapter.delete(key, config, [])} end)
      |> Enum.reject(fn {_key, result} -> result == :ok end)
      |> case do
        [] ->
          :ok

        failures ->
          {:error, {:not_deleted, Enum.map(failures, fn {k, {:error, r}} -> {k, r} end)}}
      end
    end
  end

  @doc """
  Picks the variant to serve for an HTTP `Accept` header.

  WebP is served only to a client that says it accepts WebP; everything else
  receives the first non-WebP variant. A missing header is treated as not
  accepting WebP, which is the safe answer for email clients and native apps.
  """
  @spec negotiate([stored_variant()], String.t() | nil) :: stored_variant() | nil
  def negotiate(variants, accept) do
    webp? = is_binary(accept) and String.contains?(accept, "image/webp")

    Enum.find(variants, &(webp? and &1.format == :webp)) ||
      Enum.find(variants, &(&1.format != :webp)) ||
      List.first(variants)
  end

  @doc """
  Returns a local copy of `key`, fetching it from storage on a cache miss.

  This is lazy hydration: a node with an empty local disk (a new pod, a lost
  volume) repopulates only what is actually requested, instead of copying the
  whole bucket at boot. The file is written to a temporary name and renamed
  into place, so a concurrent reader never observes a partial file.
  """
  @spec fetch_local(String.t(), String.t(), keyword()) ::
          {:ok, Path.t()} | {:error, term()}
  def fetch_local(key, cache_dir, opts) when is_binary(key) and is_binary(cache_dir) do
    with {:ok, path} <- cache_path(cache_dir, key) do
      if File.regular?(path) do
        {:ok, path}
      else
        hydrate(key, path, opts)
      end
    end
  end

  defp hydrate(key, path, opts) do
    with {:ok, config} <- fetch_config(opts),
         {:ok, %{body: body}} <- adapter(opts).get_object(key, config),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      tmp = "#{path}.#{System.unique_integer([:positive])}.tmp"

      with :ok <- File.write(tmp, body),
           :ok <- File.rename(tmp, path) do
        {:ok, path}
      else
        error ->
          File.rm(tmp)
          error
      end
    end
  end

  # Keys are built from validated segments, but a caller may pass any string
  # here, so confirm the resolved path stays inside the cache directory.
  defp cache_path(cache_dir, key) do
    root = Path.expand(cache_dir)
    path = Path.expand(key, root)

    if String.starts_with?(path, root <> "/"), do: {:ok, path}, else: {:error, :invalid_key}
  end

  defp store_all(kind, base_key, rendered, config, adapter) do
    rendered
    |> Enum.reduce_while({:ok, []}, fn variant, {:ok, stored} ->
      key = Key.variant(base_key, variant.name, variant.format)

      case adapter.put_object(key, variant.body, variant.content_type, config,
             cache_control: kind.cache_control
           ) do
        :ok ->
          {:cont, {:ok, [describe(variant, key) | stored]}}

        {:error, reason} ->
          {:halt, {:error, {:store_failed, key, reason}, stored}}
      end
    end)
    |> case do
      {:ok, stored} ->
        {:ok, Enum.reverse(stored)}

      {:error, reason, stored} ->
        Enum.each(stored, &adapter.delete(&1.key, config, []))
        {:error, reason}
    end
  end

  defp describe(variant, key) do
    %{
      name: variant.name,
      key: key,
      format: variant.format,
      content_type: variant.content_type,
      bytes: byte_size(variant.body),
      width: variant.width,
      height: variant.height
    }
  end

  defp public_url(key, config, adapter) do
    case config[:public_base_url] do
      base when is_binary(base) and base != "" ->
        String.trim_trailing(base, "/") <> "/" <> key

      _none ->
        {bucket, _prefix} = S3.bucket_and_prefix(config.bucket)
        adapter.public_url(bucket, key, config, [])
    end
  end

  defp fetch_config(opts) do
    case opts[:config] do
      config when is_map(config) -> {:ok, config}
      _missing -> {:error, :config_required}
    end
  end

  defp adapter(opts), do: Keyword.get(opts, :adapter, S3)
end
