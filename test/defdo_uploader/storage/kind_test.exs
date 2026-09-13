defmodule Defdo.Uploader.KindTest do
  # Not async: overrides are read from application env.
  use ExUnit.Case, async: false

  alias Defdo.Uploader.Kind

  setup do
    on_exit(fn -> Application.delete_env(:defdo_uploader, :kinds) end)
  end

  test "web-facing kinds store WebP for browsers plus a non-WebP fallback" do
    for name <- [:tenant_logo, :tenant_background, :user_picture] do
      {:ok, kind} = Kind.fetch(name)
      formats = Enum.map(kind.variants, & &1.format)

      assert :webp in formats, "#{name} has no WebP variant"
      assert Enum.any?(formats, &(&1 != :webp)), "#{name} has no fallback for non-WebP clients"
    end
  end

  test "platform icons are never WebP" do
    {:ok, kind} = Kind.fetch(:platform_icon)
    assert Enum.all?(kind.variants, &(&1.format == :png))
  end

  test "user pictures are private and refuse SVG" do
    {:ok, kind} = Kind.fetch(:user_picture)
    refute Kind.public?(kind)
    refute kind.allow_svg
    refute "image/svg+xml" in kind.accept
  end

  test "config merges over a built-in kind" do
    Application.put_env(:defdo_uploader, :kinds, %{user_picture: [max_bytes: 1_000]})

    {:ok, kind} = Kind.fetch(:user_picture)
    assert kind.max_bytes == 1_000
    assert kind.visibility == :private
  end

  test "config can define a new kind" do
    Application.put_env(:defdo_uploader, :kinds, %{
      product_photo: [visibility: :public, variants: [%{name: "display", format: :webp}]]
    })

    assert {:ok, %Kind{name: :product_photo, visibility: :public}} = Kind.fetch(:product_photo)
    assert :product_photo in Kind.names()
  end

  test "an unknown kind is an error" do
    assert Kind.fetch(:nope) == {:error, {:unknown_kind, :nope}}
  end
end
