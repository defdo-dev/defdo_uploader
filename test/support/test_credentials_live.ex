defmodule Defdo.Uploader.TestCredentialsLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <.live_component
      module={Defdo.Uploader.CredentialsForm}
      id="s3-creds"
      tenant_id={@tenant_id}
      connection_check={@connection_check}
    />
    """
  end

  def mount(_params, _session, socket) do
    # A test replaces the real check (four requests to a store) with a function.
    check = Application.get_env(:defdo_uploader, :test_connection_check)
    {:ok, assign(socket, tenant_id: "test-tenant-1", connection_check: check)}
  end
end
