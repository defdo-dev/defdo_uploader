defmodule Defdo.Uploader.Guard do
  @moduledoc """
  Admission checks for an upload, applied before anything is decoded or stored.

  The content type is taken from the bytes, never from the filename or the
  client-declared `Content-Type`: both are attacker-controlled, and an HTML or
  SVG document renamed to `.png` must not be admitted as a PNG.
  """

  alias Defdo.Uploader.Kind

  @svg "image/svg+xml"

  @doc """
  Admits `binary` for `kind`, returning its sniffed content type.

  Errors:

    * `{:too_large, size, max}` — larger than the kind's `max_bytes`
    * `:svg_not_allowed` — an SVG for a kind without `allow_svg`
    * `{:unsupported_type, type}` — sniffed, but not in the kind's `accept`
    * `:unrecognized_type` — not a format this package can identify
  """
  @spec admit(Kind.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  def admit(%Kind{} = kind, binary) when is_binary(binary) do
    with :ok <- check_size(kind, binary),
         {:ok, type} <- sniff(binary),
         :ok <- check_svg(kind, type) do
      check_accept(kind, type)
    end
  end

  @doc "Identifies an image by its leading bytes."
  @spec sniff(binary()) :: {:ok, String.t()} | {:error, :unrecognized_type}
  def sniff(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: {:ok, "image/png"}
  def sniff(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}
  def sniff(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: {:ok, "image/webp"}
  def sniff(<<"GIF87a", _::binary>>), do: {:ok, "image/gif"}
  def sniff(<<"GIF89a", _::binary>>), do: {:ok, "image/gif"}
  def sniff(<<_::binary-size(4), "ftypavif", _::binary>>), do: {:ok, "image/avif"}

  def sniff(binary) when is_binary(binary) do
    if svg?(binary), do: {:ok, @svg}, else: {:error, :unrecognized_type}
  end

  defp check_size(%Kind{max_bytes: max}, binary) do
    case byte_size(binary) do
      size when size > max -> {:error, {:too_large, size, max}}
      _size -> :ok
    end
  end

  defp check_svg(%Kind{allow_svg: false}, @svg), do: {:error, :svg_not_allowed}
  defp check_svg(_kind, _type), do: :ok

  defp check_accept(%Kind{accept: accept}, type) do
    if type in accept, do: {:ok, type}, else: {:error, {:unsupported_type, type}}
  end

  # An SVG may open with a BOM, whitespace, an XML declaration, comments or a
  # doctype before the root element, so look for the root element in the
  # head of the document rather than at byte zero.
  defp svg?(binary) do
    head =
      binary
      |> binary_part(0, min(byte_size(binary), 1024))
      |> String.trim_leading("﻿")
      |> String.trim_leading()
      |> String.downcase()

    (String.starts_with?(head, "<svg") or String.starts_with?(head, "<?xml") or
       String.starts_with?(head, "<!--") or String.starts_with?(head, "<!doctype svg")) and
      String.contains?(head, "<svg")
  end
end
