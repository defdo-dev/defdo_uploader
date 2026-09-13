defmodule Defdo.Uploader.StorageTest do
  use ExUnit.Case, async: true

  alias Defdo.Uploader.Storage

  @stub __MODULE__

  setup do
    config = %{
      access_key_id: "AKIATEST",
      secret_access_key: "secret",
      bucket: "assets",
      region: "auto",
      endpoint: "https://s3.test",
      req_options: [plug: {Req.Test, @stub}, retry: false]
    }

    source =
      1024 |> Image.new!(768, color: [10, 120, 200]) |> Image.write!(:memory, suffix: ".png")

    {:ok, config: config, source: source}
  end

  defp record_requests(status_for \\ fn _method, _path -> 200 end) do
    test = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(test, {
        :request,
        conn.method,
        conn.request_path,
        Map.new(conn.req_headers),
        body
      })

      Plug.Conn.send_resp(conn, status_for.(conn.method, conn.request_path), "")
    end)
  end

  describe "put/3" do
    test "stores every variant under a tenant-scoped versioned key", %{
      config: config,
      source: source
    } do
      record_requests()

      assert {:ok, stored} =
               Storage.put(:user_picture, source,
                 config: config,
                 tenant_id: "t1",
                 id: "u-1",
                 version: "v1"
               )

      assert stored.base_key == "tenants/t1/users/u-1/user_picture/v1"
      assert stored.source_type == "image/png"

      assert Enum.map(stored.variants, & &1.key) == [
               "tenants/t1/users/u-1/user_picture/v1/display.webp",
               "tenants/t1/users/u-1/user_picture/v1/fallback.jpg"
             ]

      assert_received {:request, "PUT",
                       "/assets/tenants/t1/users/u-1/user_picture/v1/display.webp", headers,
                       <<"RIFF", _::binary>>}

      assert headers["content-type"] == "image/webp"
      assert headers["cache-control"] == "private, max-age=300"

      assert_received {:request, "PUT",
                       "/assets/tenants/t1/users/u-1/user_picture/v1/fallback.jpg",
                       %{"content-type" => "image/jpeg"}, _}
    end

    test "a rejected upload never reaches storage", %{config: config} do
      record_requests()

      assert Storage.put(:user_picture, "<svg onload='x'/>",
               config: config,
               tenant_id: "t1",
               id: "u-1"
             ) == {:error, :svg_not_allowed}

      refute_received {:request, _, _, _, _}
    end

    test "a failed variant removes the variants already stored", %{
      config: config,
      source: source
    } do
      record_requests(fn
        "PUT", path -> if String.ends_with?(path, ".jpg"), do: 500, else: 200
        "DELETE", _path -> 204
      end)

      assert {:error,
              {:store_failed, "tenants/t1/users/u-1/user_picture/v1/fallback.jpg",
               {:http_status, 500}}} =
               Storage.put(:user_picture, source,
                 config: config,
                 tenant_id: "t1",
                 id: "u-1",
                 version: "v1"
               )

      assert_received {:request, "DELETE",
                       "/assets/tenants/t1/users/u-1/user_picture/v1/display.webp", _, _}
    end

    test "requires a config", %{source: source} do
      assert Storage.put(:user_picture, source, tenant_id: "t1", id: "u") ==
               {:error, :config_required}
    end
  end

  describe "url/3" do
    test "public kinds use the public base URL", %{config: config} do
      config = Map.put(config, :public_base_url, "https://cdn.example.com/")

      assert Storage.url(:tenant_logo, "tenants/t1/tenant_logo/b/v1/display.webp", config: config) ==
               {:ok, "https://cdn.example.com/tenants/t1/tenant_logo/b/v1/display.webp"}
    end

    test "public kinds without a base URL fall back to the adapter URL", %{config: config} do
      assert Storage.url(:tenant_logo, "k.webp", config: config) ==
               {:ok, "https://s3.test/assets/k.webp"}
    end

    test "private kinds are presigned and expire", %{config: config} do
      {:ok, url} =
        Storage.url(:user_picture, "tenants/t1/users/u/user_picture/v1/display.webp",
          config: config,
          expires: 120
        )

      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.path == "/assets/tenants/t1/users/u/user_picture/v1/display.webp"
      assert query["X-Amz-Expires"] == "120"
      assert is_binary(query["X-Amz-Signature"])
      refute url =~ "secret"
    end
  end

  describe "delete/2" do
    test "attempts every key and reports only the ones that still exist", %{config: config} do
      record_requests(fn "DELETE", path ->
        if String.ends_with?(path, "b.jpg"), do: 403, else: 204
      end)

      assert Storage.delete(["a.webp", "b.jpg", "c.png"], config: config) ==
               {:error, {:not_deleted, [{"b.jpg", {:http_status, 403}}]}}

      assert_received {:request, "DELETE", "/assets/a.webp", _, _}
      assert_received {:request, "DELETE", "/assets/c.png", _, _}
    end
  end

  describe "negotiate/2" do
    @variants [
      %{name: "display", format: :webp},
      %{name: "fallback", format: :jpeg}
    ]

    test "serves WebP only to clients that accept it" do
      assert Storage.negotiate(@variants, "image/avif,image/webp,*/*").format == :webp
      assert Storage.negotiate(@variants, "image/png,image/*;q=0.8").format == :jpeg
    end

    test "no Accept header gets the fallback" do
      assert Storage.negotiate(@variants, nil).format == :jpeg
    end
  end

  describe "fetch_local/3" do
    setup do
      dir = Path.join(System.tmp_dir!(), "uploader_cache_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    test "hydrates on a miss, then serves from disk", %{config: config, dir: dir} do
      test = self()

      Req.Test.stub(@stub, fn conn ->
        send(test, {:get, conn.request_path})

        conn
        |> Plug.Conn.put_resp_content_type("image/webp", nil)
        |> Plug.Conn.send_resp(200, "webp-bytes")
      end)

      key = "tenants/t1/tenant_logo/b/v1/display.webp"

      assert {:ok, path} = Storage.fetch_local(key, dir, config: config)
      assert File.read!(path) == "webp-bytes"
      assert_received {:get, "/assets/" <> ^key}

      assert {:ok, ^path} = Storage.fetch_local(key, dir, config: config)
      refute_received {:get, _}
    end

    test "a missing object is not cached", %{config: config, dir: dir} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert Storage.fetch_local("missing.webp", dir, config: config) == {:error, :not_found}
      refute File.exists?(Path.join(dir, "missing.webp"))
    end

    test "a key cannot escape the cache directory", %{config: config, dir: dir} do
      Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)

      assert Storage.fetch_local("../../etc/passwd", dir, config: config) ==
               {:error, :invalid_key}
    end
  end
end
