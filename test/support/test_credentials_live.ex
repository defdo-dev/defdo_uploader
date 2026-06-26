defmodule Defdo.Uploader.TestCredentialsLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <.live_component
      module={Defdo.Uploader.CredentialsForm}
      id="s3-creds"
      tenant_id={@tenant_id}
    />
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, tenant_id: "test-tenant-1")}
  end
end
