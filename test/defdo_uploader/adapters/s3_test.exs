defmodule Defdo.Uploader.Adapters.S3Test do
  use ExUnit.Case, async: true

  alias Defdo.Uploader.Adapters.S3

  @stub __MODULE__

  setup do
    path =
      Path.join(System.tmp_dir!(), "defdo_uploader_s3_#{System.unique_integer([:positive])}.png")

    File.write!(path, "png-bytes")
    on_exit(fn -> File.rm(path) end)

    config = %{
      access_key_id: "AKIATEST",
      secret_access_key: "secret",
      bucket: "assets",
      region: "auto",
      endpoint: "https://s3.test",
      req_options: [plug: {Req.Test, @stub}, retry: false]
    }

    {:ok, path: path, config: config}
  end

  describe "upload_file/3" do
    test "uploads, then reads back metadata from HEAD", %{path: path, config: config} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/assets/tenants/t1/logo.png"
        assert [_signed] = Plug.Conn.get_req_header(conn, "authorization")

        case conn.method do
          "PUT" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "png-bytes"
            assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]
            Plug.Conn.send_resp(conn, 200, "")

          "HEAD" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "image/png")
            |> Plug.Conn.put_resp_header("etag", ~s("abc"))
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      assert {:ok, result} = S3.upload_file(path, "tenants/t1/logo.png", config)
      assert result.object_key == "tenants/t1/logo.png"
      assert result.content_type == "image/png"
      assert result.etag == ~s("abc")
      assert result.url == "https://s3.test/assets/tenants/t1/logo.png"
    end

    test "a rejected PUT is an error even when an older object still exists",
         %{path: path, config: config} do
      # Before the status check, the 403 fell through to HEAD, which found the
      # previous object and reported success with its stale metadata.
      Req.Test.stub(@stub, fn conn ->
        case conn.method do
          "PUT" -> Plug.Conn.send_resp(conn, 403, "AccessDenied")
          "HEAD" -> Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      assert S3.upload_file(path, "tenants/t1/logo.png", config) ==
               {:error, {:http_status, 403}}
    end

    test "a missing local file never reaches the network", %{config: config} do
      Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)

      assert S3.upload_file("/nonexistent/file.png", "k", config) == {:error, :file_not_found}
    end

    test "keeps ignoring the bucket prefix, which callers already put in the key",
         %{path: path, config: config} do
      # defdo_theme_hub and defdo_cms join the prefix into the object key
      # themselves and pass "bucket/prefix" as the bucket. Applying the prefix
      # here as well would write to prefix/prefix/...
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/assets/cms/site/logo.png"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, _} =
               S3.upload_file(path, "cms/site/logo.png", %{config | bucket: "assets/cms"})
    end
  end

  describe "delete_object/2" do
    test "succeeds on 204", %{config: config} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "DELETE"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert S3.delete_object("tenants/t1/logo.png", config) == :ok
    end

    test "treats an already-missing object as deleted", %{config: config} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 404, "NoSuchKey") end)

      assert S3.delete_object("tenants/t1/gone.png", config) == :ok
    end

    test "a refused delete is an error, so callers keep their row", %{config: config} do
      # This used to return :ok, and consumers then deleted the database row
      # while the object stayed in the bucket forever.
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 403, "AccessDenied") end)

      assert S3.delete_object("tenants/t1/logo.png", config) == {:error, {:http_status, 403}}
    end

    test "a server error is an error", %{config: config} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert S3.delete_object("tenants/t1/logo.png", config) == {:error, {:http_status, 500}}
    end

    test "an empty key is still a no-op", %{config: config} do
      Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)

      assert S3.delete_object("", config) == :ok
    end

    test "missing credentials never reach the network", %{config: config} do
      Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)

      assert S3.delete_object("k", %{config | secret_access_key: ""}) ==
               {:error, :missing_credentials}
    end
  end

  describe "head_object/2" do
    test "maps 404 to :not_found", %{config: config} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert S3.head_object("missing.png", config) == {:error, :not_found}
    end

    test "parses content-length", %{config: config} do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-length", "1234")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, %{content_length: 1234}} = S3.head_object("logo.png", config)
    end
  end

  describe "upload_one/4" do
    test "a rejected PUT is reported against its key", %{path: path, config: config} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 403, "") end)

      {:ok, client} = S3.client(config)

      assert S3.upload_one(client, "assets", "k.png", path) ==
               {:error, {"k.png", {:http_status, 403}}}
    end

    test "returns the key on success", %{path: path, config: config} do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

      {:ok, client} = S3.client(config)

      assert S3.upload_one(client, "assets", "k.png", path) == {:ok, "k.png"}
    end
  end
end
