defmodule Defdo.Uploader.ImagePipeline do
  @moduledoc """
  Renders an admitted upload into a kind's variants.

  Every variant is **re-encoded**, including one kept at its original size.
  Re-encoding is what makes the stored object safe to serve: it discards EXIF
  and XMP metadata (camera GPS coordinates included), any bytes appended after
  the image data, and any polyglot payload that only survives byte-for-byte
  copies. EXIF orientation is applied to the pixels first, so a portrait photo
  does not come out sideways once its metadata is gone.

  Requires the optional `:image` dependency (libvips). Without it every call
  returns `{:error, :image_library_unavailable}` rather than silently storing
  the upload unprocessed.
  """

  alias Defdo.Uploader.{Key, Kind}

  @compile {:no_warn_undefined, [Image]}

  @type rendered :: %{
          name: String.t(),
          format: :webp | :png | :jpeg,
          body: binary(),
          content_type: String.t(),
          width: pos_integer(),
          height: pos_integer()
        }

  @doc "Whether the `:image` dependency is loaded."
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Image)

  @doc "Renders every variant of `kind` from an admitted `binary`."
  @spec render(Kind.t(), binary()) :: {:ok, [rendered()]} | {:error, term()}
  def render(%Kind{} = kind, binary) when is_binary(binary) do
    if available?() do
      with {:ok, image} <- decode(kind, binary) do
        render_variants(kind.variants, image)
      end
    else
      {:error, :image_library_unavailable}
    end
  end

  defp decode(kind, binary) do
    with {:ok, image} <- Image.from_binary(binary),
         :ok <- check_pixels(kind, image),
         {:ok, {image, _flags}} <- Image.autorotate(image) do
      {:ok, image}
    else
      {:error, {:too_many_pixels, _, _}} = error -> error
      {:error, reason} -> {:error, {:undecodable, reason}}
    end
  end

  # libvips reads the header lazily, so width and height are known before the
  # pixel data is decoded — which is what lets this reject a decompression
  # bomb before it allocates anything.
  defp check_pixels(%Kind{max_pixels: max}, image) do
    case Image.width(image) * Image.height(image) do
      pixels when pixels > max -> {:error, {:too_many_pixels, pixels, max}}
      _pixels -> :ok
    end
  end

  defp render_variants(variants, image) do
    Enum.reduce_while(variants, {:ok, []}, fn variant, {:ok, acc} ->
      case render_variant(variant, image) do
        {:ok, rendered} -> {:cont, {:ok, [rendered | acc]}}
        {:error, reason} -> {:halt, {:error, {:variant_failed, variant.name, reason}}}
      end
    end)
    |> case do
      {:ok, rendered} -> {:ok, Enum.reverse(rendered)}
      error -> error
    end
  end

  defp render_variant(variant, image) do
    with {:ok, image} <- resize(image, variant),
         {:ok, image} <- flatten_for(image, variant.format),
         {:ok, body} <- Image.write(image, :memory, write_options(variant)) do
      {:ok,
       %{
         name: variant.name,
         format: variant.format,
         body: body,
         content_type: content_type(variant.format),
         width: Image.width(image),
         height: Image.height(image)
       }}
    end
  end

  defp resize(image, %{width: width} = variant) do
    # `resize: :down` never upscales: a 200px logo stays 200px rather than
    # being blurred up to the variant's box.
    Image.thumbnail(image, width,
      height: Map.get(variant, :height, width),
      fit: Map.get(variant, :fit, :contain),
      resize: :down,
      autorotate: false
    )
  end

  defp resize(image, _variant), do: {:ok, image}

  # JPEG has no alpha channel. Without an explicit background libvips fills
  # transparency with black, which turns a transparent logo into a black box.
  defp flatten_for(image, :jpeg), do: Image.flatten(image, background: :white)
  defp flatten_for(image, _format), do: {:ok, image}

  defp write_options(variant) do
    [suffix: "." <> Key.extension(variant.format), strip_metadata: true]
    |> maybe_quality(variant)
  end

  defp maybe_quality(options, %{format: :png}), do: options
  defp maybe_quality(options, %{quality: quality}), do: Keyword.put(options, :quality, quality)
  defp maybe_quality(options, _variant), do: options

  defp content_type(:webp), do: "image/webp"
  defp content_type(:png), do: "image/png"
  defp content_type(:jpeg), do: "image/jpeg"
end
