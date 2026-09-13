defmodule Defdo.Uploader.GuardTest do
  use ExUnit.Case, async: true

  alias Defdo.Uploader.{Guard, Kind}

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "rest">>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, "rest">>
  @webp <<"RIFF", 0, 0, 0, 0, "WEBP", "VP8 ">>

  describe "sniff/1" do
    test "identifies raster formats by their magic bytes" do
      assert Guard.sniff(@png) == {:ok, "image/png"}
      assert Guard.sniff(@jpeg) == {:ok, "image/jpeg"}
      assert Guard.sniff(@webp) == {:ok, "image/webp"}
      assert Guard.sniff("GIF89a...") == {:ok, "image/gif"}
    end

    test "finds an SVG root behind a BOM, whitespace or an XML declaration" do
      assert Guard.sniff("<svg xmlns='http://www.w3.org/2000/svg'/>") == {:ok, "image/svg+xml"}
      assert Guard.sniff("﻿  \n<svg/>") == {:ok, "image/svg+xml"}
      assert Guard.sniff(~s(<?xml version="1.0"?>\n<svg/>)) == {:ok, "image/svg+xml"}
    end

    test "an HTML document is not an image, whatever it is named" do
      assert Guard.sniff("<html><script>alert(1)</script></html>") ==
               {:error, :unrecognized_type}

      assert Guard.sniff(~s(<?xml version="1.0"?><html/>)) == {:error, :unrecognized_type}
    end
  end

  describe "admit/2" do
    test "admits an accepted type and returns the sniffed type" do
      {:ok, kind} = Kind.fetch(:user_picture)
      assert Guard.admit(kind, @jpeg) == {:ok, "image/jpeg"}
    end

    test "rejects SVG for a kind that does not allow it" do
      {:ok, kind} = Kind.fetch(:user_picture)
      assert Guard.admit(kind, "<svg onload='alert(1)'/>") == {:error, :svg_not_allowed}
    end

    test "admits SVG for a kind that allows it" do
      {:ok, kind} = Kind.fetch(:tenant_logo)
      assert Guard.admit(kind, "<svg/>") == {:ok, "image/svg+xml"}
    end

    test "rejects a recognised type the kind does not accept" do
      {:ok, kind} = Kind.fetch(:user_picture)
      assert Guard.admit(kind, "GIF89a...") == {:error, {:unsupported_type, "image/gif"}}
    end

    test "rejects an oversized upload before sniffing it" do
      kind = %Kind{name: :tiny, max_bytes: 4}
      assert Guard.admit(kind, @png) == {:error, {:too_large, byte_size(@png), 4}}
    end
  end
end
