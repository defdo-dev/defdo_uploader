defmodule Defdo.Uploader.CredentialsFormTest.MemoryBackend do
  @behaviour Defdo.Uploader.CredentialsBackend

  @impl true
  def put(creds, _opts) do
    send(Application.fetch_env!(:defdo_uploader, :test_pid), {:put, creds})
    :ok
  end

  @impl true
  def get(_opts), do: :error

  @impl true
  def present?(_opts), do: false
end

defmodule Defdo.Uploader.CredentialsFormTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint Defdo.Uploader.TestEndpoint

  @passed %{
    ok?: true,
    leftover: nil,
    steps:
      for(step <- [:connect, :write, :edit, :delete], do: %{step: step, status: :ok, reason: nil})
  }

  setup do
    test_pid = self()

    Application.put_env(:defdo_uploader, :test_connection_check, fn config, opts ->
      send(test_pid, {:checked, config})
      result = Application.get_env(:defdo_uploader, :test_check_result, @passed)
      # report progress the way the real check does
      for step <- result.steps, do: opts[:on_step].(step)
      result
    end)

    on_exit(fn ->
      Application.delete_env(:defdo_uploader, :test_connection_check)
      Application.delete_env(:defdo_uploader, :test_check_result)
    end)

    {:ok, lv, _html} = live_isolated(build_conn(), Defdo.Uploader.TestCredentialsLive)
    %{lv: lv}
  end

  describe "mount" do
    test "renders the form with all fields", %{lv: lv} do
      html = render(lv)

      assert html =~ "Access Key ID"
      assert html =~ "Secret Access Key"
      assert html =~ "Bucket"
      assert html =~ "Region"
      assert html =~ "Endpoint URL"
    end

    test "shows Test Connection button", %{lv: lv} do
      html = render(lv)
      assert html =~ "Test Connection"
    end

    test "shows Save Credentials button", %{lv: lv} do
      html = render(lv)
      assert html =~ "Save Credentials"
    end
  end

  describe "validation" do
    test "renders form with empty values initially", %{lv: lv} do
      html = render(lv)

      # Fields are rendered with nil values — Phoenix.HTML.Form omits
      # the value attribute for nil. Verify the input elements exist.
      assert html =~ "name=\"creds[access_key_id]\""
      assert html =~ "name=\"creds[secret_access_key]\""
      assert html =~ "name=\"creds[bucket]\""
      assert html =~ "name=\"creds[region]\""
      assert html =~ "name=\"creds[endpoint]\""
    end
  end

  describe "Test Connection" do
    test "a click without form params does not crash and renders a result", %{lv: lv} do
      html = lv |> with_target("#s3-creds") |> render_hook("test", %{"value" => ""})

      assert Process.alive?(lv.pid)
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "runs the check with the form values and lists every step", %{lv: lv} do
      lv |> form("#creds-form", creds: valid_params()) |> render_submit(%{"intent" => "test"})
      html = render_async(lv)

      assert_received {:checked, %{bucket: bucket, access_key_id: _}}
      assert bucket == valid_params()["bucket"]

      assert html =~ "Connection verified"

      for step <- ~w(connect write edit delete) do
        assert has_element?(lv, "#s3-creds-test-result li[data-step='#{step}'][data-status='ok']")
      end

      refute html =~ "Credentials saved"
    end

    test "a failed step is named with its reason and the later ones are not run", %{lv: lv} do
      Application.put_env(:defdo_uploader, :test_check_result, %{
        ok?: false,
        leftover: nil,
        steps: [
          %{step: :connect, status: :ok, reason: nil},
          %{step: :write, status: :error, reason: {:http_status, 403}},
          %{step: :edit, status: :skipped, reason: nil},
          %{step: :delete, status: :skipped, reason: nil}
        ]
      })

      lv |> form("#creds-form", creds: valid_params()) |> render_submit(%{"intent" => "test"})
      html = render_async(lv)

      assert html =~ "Connection test failed"
      assert has_element?(lv, "li[data-step='write'][data-status='error']", "access denied (403)")
      assert has_element?(lv, "li[data-step='edit'][data-status='skipped']")
      refute html =~ "Connection verified"
    end

    test "a check that crashes is reported, not left spinning", %{lv: lv} do
      Application.put_env(:defdo_uploader, :test_connection_check, fn _config, _opts ->
        raise "boom"
      end)

      {:ok, lv2, _html} = live_isolated(build_conn(), Defdo.Uploader.TestCredentialsLive)

      lv2 |> form("#creds-form", creds: valid_params()) |> render_submit(%{"intent" => "test"})
      html = render_async(lv2)

      assert html =~ "Connection test failed"
      assert html =~ "the test could not run"
      refute html =~ "Testing..."
      assert Process.alive?(lv.pid)
    end

    test "a host with a :check_view slot presents the states and can dismiss them" do
      {:ok, lv, _html} = live_isolated(build_conn(), Defdo.Uploader.TestCredentialsSlotLive)

      lv |> form("#creds-form", creds: valid_params()) |> render_submit(%{"intent" => "test"})
      render_async(lv)

      # the host's markup, not the component's
      assert has_element?(lv, "dialog#host-check[data-status='passed']")
      refute has_element?(lv, "#s3-creds-test-result")

      for step <- ~w(connect write edit delete) do
        assert has_element?(lv, "#host-check li[data-step='#{step}'][data-status='ok']")
      end

      assert has_element?(lv, "#host-check li", "Write a test object: ok")

      lv |> element("#host-check-close") |> render_click()
      refute has_element?(lv, "#host-check")
    end

    test "the secret is never rendered back", %{lv: lv} do
      html =
        lv
        |> form("#creds-form", creds: valid_params())
        |> render_submit(%{"intent" => "test"})

      refute html =~ "TOPSECRETVALUE"
      refute render_async(lv) =~ "TOPSECRETVALUE"
      html = lv |> form("#creds-form", creds: valid_params()) |> render_change()
      refute html =~ "TOPSECRETVALUE"
    end
  end

  describe "buttons" do
    test "use daisyUI classes, not palette utilities", %{lv: lv} do
      html = render(lv)

      assert html =~ "btn btn-primary"
      assert html =~ "btn btn-outline"
      refute html =~ "bg-blue-600"
      refute html =~ "bg-green-600"
    end
  end

  describe "empty submit" do
    test "renders field errors", %{lv: lv} do
      html = lv |> form("#creds-form", creds: %{}) |> render_submit()

      assert has_element?(lv, "#creds_access_key_id-error")
      assert has_element?(lv, "#creds_secret_access_key-error")
      assert has_element?(lv, "#creds_bucket-error")
      refute has_element?(lv, "#creds_region-error")
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end

  describe "region" do
    test "a blank region is accepted and stored with the client default", %{lv: lv} do
      Application.put_env(:defdo_uploader, :test_pid, self())

      Application.put_env(
        :defdo_uploader,
        :credentials_backend,
        Defdo.Uploader.CredentialsFormTest.MemoryBackend
      )

      on_exit(fn ->
        Application.put_env(:defdo_uploader, :credentials_backend, Defdo.Uploader.DefaultBackend)
      end)

      html =
        lv
        |> form("#creds-form", creds: Map.put(valid_params(), "region", ""))
        |> render_submit()

      assert html =~ "Credentials saved"
      assert_received {:put, %{region: "us-east-1", bucket: "my-bucket"}}
      refute html =~ "TOPSECRETVALUE"
    end

    test "a save the backend rejects is reported, not shown as saved", %{lv: lv} do
      html = lv |> form("#creds-form", creds: valid_params()) |> render_submit()

      refute html =~ "Credentials saved"
      assert html =~ "Could not save"
    end
  end

  defp valid_params do
    %{
      "access_key_id" => "AKIATESTKEY",
      "secret_access_key" => "TOPSECRETVALUE",
      "bucket" => "my-bucket",
      "region" => "",
      "endpoint" => "https://example.r2.test"
    }
  end
end
