defmodule Defdo.Uploader.ImagePipelineTest do
  use ExUnit.Case, async: true

  alias Defdo.Uploader.{ImagePipeline, Kind}
  alias Vix.Vips.MutableImage

  defp png(width, height, color \\ [200, 30, 30, 255]) do
    width |> Image.new!(height, color: color) |> Image.write!(:memory, suffix: ".png")
  end

  defp decode!(body), do: Image.from_binary!(body)

  test "renders the user picture as square WebP and JPEG, cropped to cover" do
    {:ok, kind} = Kind.fetch(:user_picture)

    assert {:ok, [display, fallback]} = ImagePipeline.render(kind, png(2000, 1000))

    assert %{name: "display", format: :webp, content_type: "image/webp"} = display
    assert %{name: "fallback", format: :jpeg, content_type: "image/jpeg"} = fallback
    assert {display.width, display.height} == {512, 512}
    assert {fallback.width, fallback.height} == {512, 512}

    assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = display.body
    assert <<0xFF, 0xD8, 0xFF, _::binary>> = fallback.body
  end

  test "a logo keeps its aspect ratio instead of being stretched into the box" do
    {:ok, kind} = Kind.fetch(:tenant_logo)

    {:ok, [display | _]} = ImagePipeline.render(kind, png(2048, 1024))

    assert {display.width, display.height} == {1024, 512}
  end

  test "never upscales a small source" do
    {:ok, kind} = Kind.fetch(:tenant_logo)

    {:ok, [display | _]} = ImagePipeline.render(kind, png(200, 100))

    assert {display.width, display.height} == {200, 100}
  end

  test "WebP is materially smaller than the PNG fallback for the same logo" do
    {:ok, kind} = Kind.fetch(:tenant_logo)
    # A gradient gives the encoders real content to work on; a flat colour
    # compresses to almost nothing in every format and proves nothing.
    {:ok, gradient} = Image.linear_gradient(1024, 1024)
    source = Image.write!(gradient, :memory, suffix: ".png")

    {:ok, [display, fallback]} = ImagePipeline.render(kind, source)

    assert byte_size(display.body) < byte_size(fallback.body)
  end

  test "transparency becomes white in JPEG, not black" do
    kind = %Kind{name: :t, variants: [%{name: "f", format: :jpeg, quality: 90}]}
    transparent = png(8, 8, [0, 0, 0, 0])

    {:ok, [jpeg]} = ImagePipeline.render(kind, transparent)

    assert {:ok, [r, g, b]} = jpeg.body |> decode!() |> Image.get_pixel(0, 0)
    assert r > 240 and g > 240 and b > 240
  end

  test "EXIF metadata, where camera GPS coordinates live, is stripped" do
    {:ok, kind} = Kind.fetch(:user_picture)
    marker = "GPS-51.5007N-0.1246W"

    {:ok, image} =
      64
      |> Image.new!(64, color: [10, 20, 30])
      |> Image.mutate(fn mutable ->
        MutableImage.set(mutable, "exif-ifd0-ImageDescription", :gchararray, marker)
      end)

    source = Image.write!(image, :memory, suffix: ".jpg", strip_metadata: false)

    # Guard the precondition, or this test would pass against a source that
    # never carried metadata in the first place.
    assert source =~ marker
    assert source =~ "Exif"

    {:ok, variants} = ImagePipeline.render(kind, source)

    for variant <- variants do
      refute variant.body =~ marker, "#{variant.name} kept the EXIF payload"
      refute variant.body =~ "Exif", "#{variant.name} kept an EXIF block"
    end
  end

  test "bytes appended after the image do not survive re-encoding" do
    # A polyglot payload rides along behind valid image data and survives any
    # byte-for-byte copy. Re-encoding rebuilds the file from pixels only.
    {:ok, kind} = Kind.fetch(:user_picture)
    payload = "<script>alert(document.cookie)</script>"

    {:ok, variants} = ImagePipeline.render(kind, png(64, 64) <> payload)

    for variant <- variants, do: refute(variant.body =~ payload)
  end

  test "rasterises an SVG for a kind that allows it" do
    {:ok, kind} = Kind.fetch(:tenant_logo)

    svg =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200"><rect width="400" height="200" fill="red"/></svg>)

    {:ok, [display, fallback]} = ImagePipeline.render(kind, svg)

    assert display.format == :webp and fallback.format == :png
    refute fallback.body =~ "<svg"
  end

  test "rejects a pixel grid larger than the kind allows, before decoding it" do
    kind = %Kind{name: :t, max_pixels: 100, variants: [%{name: "f", format: :png}]}

    assert ImagePipeline.render(kind, png(20, 20)) == {:error, {:too_many_pixels, 400, 100}}
  end

  test "undecodable bytes are an error, not a crash" do
    {:ok, kind} = Kind.fetch(:user_picture)

    assert {:error, {:undecodable, _}} =
             ImagePipeline.render(kind, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "garbage">>)
  end
end
