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

  setup do
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

    test "uses the current form values and shows the result inside the component", %{lv: lv} do
      html =
        lv
        |> form("#creds-form", creds: valid_params())
        |> render_submit(%{"intent" => "test"})

      assert html =~ "Connected"
      assert has_element?(lv, "#s3-creds-test-result")
      refute html =~ "Credentials saved"
    end

    test "the secret is never rendered back", %{lv: lv} do
      html =
        lv
        |> form("#creds-form", creds: valid_params())
        |> render_submit(%{"intent" => "test"})

      refute html =~ "TOPSECRETVALUE"
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
