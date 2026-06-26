defmodule Defdo.Uploader.CredentialsFormTest do
  use ExUnit.Case, async: true
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

      assert html =~ ~s(value="")
    end
  end
end
