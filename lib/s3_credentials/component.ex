defmodule Defdo.Uploader.CredentialsForm do
  @moduledoc """
  Embeddable S3 credentials admin form.

  LiveComponent that provides a complete credentials management UI:
  form fields, "Test Connection" button, save, and connection status.

  ## Usage

      <.live_component
        module={Defdo.Uploader.CredentialsForm}
        id="s3-creds"
        tenant_id={@tenant_id}
        return_to={~p"/admin"}
      />

  ## Customization

  Wrap the component with your own layout chrome:

      <.live_component module={Defdo.Uploader.CredentialsForm} id="s3" tenant_id={@tid}>
        <:header>My App S3 Setup</:header>
        <:footer>
          <.link navigate={~p"/admin"}>Back to Admin</.link>
        </:footer>
      </.live_component>
  """

  use Phoenix.LiveComponent

  alias Defdo.Uploader.Adapters.S3
  alias Defdo.Uploader.S3Credentials

  @default_fields %{
    "access_key_id" => nil,
    "secret_access_key" => nil,
    "bucket" => nil,
    "region" => nil,
    "endpoint" => nil
  }

  @impl true
  def update(%{tenant_id: tenant_id} = assigns, socket) do
    creds = load_creds(tenant_id)
    config = build_config(creds)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:config, config)
     |> assign(:creds, creds)
     |> assign(:form, to_form(changeset(creds), as: "creds"))
     |> assign(:testing?, false)
     |> assign(:saving?, false)
     |> maybe_subscribe(tenant_id)}
  end

  @impl true
  def handle_event("validate", %{"creds" => params}, socket) do
    cs = changeset(params)
    {:noreply, assign(socket, form: to_form(cs, as: "creds"))}
  end

  def handle_event("test", %{"creds" => params}, socket) do
    if valid?(params) do
      attrs = normalize(params)
      send(self(), {:test_connection, attrs})

      {:noreply,
       socket
       |> assign(:form, to_form(params_to_map(params), as: "creds"))
       |> assign(:testing?, true)
       |> assign(:test_result, nil)}
    else
      {:noreply, assign(socket, form: to_form(params_to_map(params), as: "creds"))}
    end
  end

  def handle_event("save", %{"creds" => params}, socket) do
    if valid?(params) do
      attrs = normalize(params)
      S3Credentials.put(attrs, tenant_id: socket.assigns.tenant_id)
      broadcast_update(socket.assigns.tenant_id)

      {:noreply,
       socket
       |> assign(:form, to_form(params_to_map(params), as: "creds"))
       |> assign(:saving?, false)
       |> assign(:saved?, true)
       |> assign(:creds, attrs)}
    else
      {:noreply, assign(socket, form: to_form(params_to_map(params), as: "creds"))}
    end
  end

  @impl true
  def handle_info({:test_connection, attrs}, socket) do
    result =
      case S3.validate_credentials(attrs) do
        {:ok, info} -> {:ok, info}
        {:error, reason} -> {:error, reason}
      end

    {:noreply,
     socket
     |> assign(:testing?, false)
     |> assign(:test_result, result)}
  end

  def handle_info({:credentials_updated, _payload}, socket) do
    creds = load_creds(socket.assigns.tenant_id)
    {:noreply, assign(socket, :creds, creds)}
  end

  # ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-6">
      <div :if={@test_result} class={[
        "rounded-lg p-4 text-sm",
        if(match?({:ok, _}, @test_result), do: "bg-green-50 text-green-800", else: "bg-red-50 text-red-800")
      ]}>
        <%= if match?({:ok, _}, @test_result) do %>
          <strong>Connected</strong>
          <span :if={test_key(@test_result)}> — test key: <%= test_key(@test_result) %></span>
        <% else %>
          <strong>Error</strong> — <%= humanize(@test_result) %>
        <% end %>
      </div>

      <form phx-change="validate" phx-submit="save" phx-target={@myself}>
        <.input field={@form[:access_key_id]} label="Access Key ID" />
        <.input field={@form[:secret_access_key]} label="Secret Access Key" type="password" />
        <.input field={@form[:bucket]} label="Bucket" />
        <.input field={@form[:region]} label="Region" />
        <.input field={@form[:endpoint]} label="Endpoint URL" />

        <div class="mt-4 flex gap-3">
          <.button type="button" phx-click="test" phx-target={@myself} disabled={@testing?}>
            <%= if @testing?, do: "Testing...", else: "Test Connection" %>
          </.button>
          <.button type="submit" disabled={@saving?}>
            <%= if @saving?, do: "Saving...", else: "Save Credentials" %>
          </.button>
        </div>
      </form>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp load_creds(tenant_id) do
    case S3Credentials.get(tenant_id: tenant_id) do
      {:ok, creds} -> creds
      _ -> @default_fields
    end
  end

  defp valid?(params) when is_map(params) do
    required = ~w(access_key_id secret_access_key bucket region)
    Enum.all?(required, fn k -> present?(params[k]) end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp normalize(params) when is_map(params) do
    %{
      access_key_id: params["access_key_id"],
      secret_access_key: params["secret_access_key"],
      bucket: params["bucket"],
      region: params["region"],
      endpoint: params["endpoint"]
    }
  end

  defp params_to_map(params) when is_map(params), do: Map.new(params, fn {k, v} -> {k, v} end)

  defp changeset(creds) do
    data = Map.merge(@default_fields, creds || @default_fields)
    data |> Map.new(fn {k, v} -> {k, v} end)
  end

  defp test_key({:ok, info}) when is_map(info), do: info[:test_key]
  defp test_key(_), do: nil

  defp humanize({:error, reason}), do: inspect(reason)
  defp humanize(_), do: "Unknown error"

  defp broadcast_update(tenant_id) do
    if Code.ensure_loaded?(Defdo.Tenant.Boundary.PubSub) do
      topic = topic(tenant_id)
      Phoenix.PubSub.broadcast(pubsub(), topic, {:credentials_updated, %{}})
    end
  end

  defp maybe_subscribe(socket, tenant_id) do
    if Code.ensure_loaded?(Defdo.Tenant.Boundary.PubSub) do
      topic = topic(tenant_id)
      Phoenix.PubSub.subscribe(pubsub(), topic)
    end

    socket
  end

  defp pubsub do
    Application.get_env(:defdo_uploader, :pubsub, Defdo.Uploader.PubSub)
  end

  def topic(tenant_id) when is_binary(tenant_id), do: "uploader:tenant:#{tenant_id}"
  def topic(_), do: "uploader:global"
end
