defmodule Defdo.Uploader.CredentialsForm do
  use Defdo.Uploader, :live_component

  alias Defdo.Uploader.S3Credentials
  alias Defdo.Uploader.Adapters.S3

  @default_fields %{
    access_key_id: nil,
    secret_access_key: nil,
    bucket: nil,
    region: nil,
    endpoint: nil
  }

  @impl true
  def mount(socket) do
    creds = load_creds(socket.assigns.tenant_id)
    {:ok, assign(socket, form: to_form(changeset(creds), as: "creds"))}
  end

  @impl true
  def handle_event("validate", %{"creds" => params}, socket) do
    cs = changeset(params)
    {:noreply, assign(socket, form: to_form(cs, as: "creds"))}
  end

  def handle_event("save", %{"creds" => params} = payload, socket) do
    # simplified: test + save in same handler
  end

  def handle_event("test", _params, socket) do
    # test handler
  end

  def handle_event("save", _params, socket) do
    # save handler
  end

  defp load_creds(socket, tenant_id) do
    # load existing creds
  end

  defp changeset(attrs) do
    # build changeset
  end

  defp to_attrs(cs) do
    # convert changeset to attrs
  end

  defp humanize_error(reason) do
    # format error
  end

  defp maybe_subscribe(socket, tenant_id) do
    # subscribe if needed
  end
end
