defmodule Defdo.Uploader.CredentialsForm do
  @moduledoc """
  Embeddable S3 credentials admin form.

  LiveComponent that provides a complete credentials management UI:
  form fields, "Test Connection" button, save, and connection status.

  Test Connection and Save work from the values currently in the form and report their
  outcome inside the component; the host does not need to handle any message. A secret is
  never rendered back into the HTML: the Secret Access Key input is always empty, and leaving
  it blank on save or test keeps the stored secret.

  Region is optional (S3-compatible stores such as R2 or MinIO may not use one); a blank
  region is stored as `"us-east-1"`, the same default the S3 client uses.

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

  ## Test Connection

  The check itself is `Defdo.Uploader.ConnectionCheck` (connect, write, edit, delete with one
  throwaway object). By default the component lists the steps above the form. A host that wants
  its own presentation (a dialog, say) gives a `:check_view` slot; it receives the live state and
  the component renders nothing for the check itself:

      <:check_view :let={check}>
        <dialog open>
          <p :for={step <- check.steps}>{step.label}: {step.detail}</p>
          <button phx-click={check.dismiss} phx-target={check.target}>Close</button>
        </dialog>
      </:check_view>

  `check.status` is `:running | :passed | :failed`; each of `check.steps` has `step`, `status`
  (`:pending | :running | :ok | :error | :skipped`), `label` and `detail` (words, never a
  credential); `check.leftover` is the key of a test object the store refused to delete, or nil.
  """

  use Phoenix.LiveComponent

  alias Defdo.Uploader.ConnectionCheck
  alias Defdo.Uploader.S3Credentials

  @default_region "us-east-1"
  @fields ~w(access_key_id secret_access_key bucket region endpoint)
  @required ~w(access_key_id secret_access_key bucket)

  # A step of the running check, sent by the check's task (`send_update/3`).
  @impl true
  def update(%{check_step: %{step: name} = step}, socket) do
    case socket.assigns[:check] do
      %{status: :running, steps: steps} = check ->
        steps = Enum.map(steps, &if(&1.step == name, do: described(step), else: &1))
        {:ok, assign(socket, :check, %{check | steps: steps})}

      # dismissed, or already finished: a late step changes nothing
      _ ->
        {:ok, socket}
    end
  end

  def update(%{tenant_id: tenant_id} = assigns, socket) do
    creds = load_creds(tenant_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:creds, creds)
     |> assign(:params, stored_params(creds))
     |> assign(:errors, %{})
     |> assign(:check, nil)
     |> assign(:save_result, nil)
     |> assign(:saving?, false)
     |> maybe_subscribe(tenant_id)}
  end

  @impl true
  def handle_event("validate", %{"creds" => params}, socket) do
    {:noreply, assign(socket, :params, clean_params(params))}
  end

  # The submit button named `intent=test` is the Test Connection control. A bare `test` click
  # (no form params) is answered from the last values the form reported.
  def handle_event("test", %{"creds" => params}, socket),
    do: run_test(clean_params(params), socket)

  def handle_event("test", _params, socket), do: run_test(socket.assigns.params, socket)

  def handle_event("save", %{"creds" => params} = event, socket) do
    params = clean_params(params)

    if event["intent"] == "test",
      do: run_test(params, socket),
      else: run_save(params, socket)
  end

  def handle_event("save", _params, socket), do: run_save(socket.assigns.params, socket)

  # The host's own presentation of the check (the `:check` slot) closes it with this.
  def handle_event("dismiss_check", _params, socket), do: {:noreply, assign(socket, :check, nil)}

  defp run_test(params, socket) do
    socket = assign(socket, :params, params) |> assign(:save_result, nil)
    attrs = normalize(params, socket.assigns.creds)

    case errors(attrs) do
      errors when map_size(errors) > 0 ->
        {:noreply, socket |> assign(:errors, errors) |> assign(:check, nil)}

      _ ->
        # Four real requests (connect, write, edit, delete) can take seconds,
        # so they run off the LiveView process.
        check = socket.assigns[:connection_check] || (&ConnectionCheck.run/2)
        view = self()
        myself = socket.assigns.myself

        on_step = fn step ->
          Phoenix.LiveView.send_update(view, myself, check_step: step)
        end

        pending =
          for step <- ConnectionCheck.steps(), do: described(%{step: step, status: :pending})

        {:noreply,
         socket
         |> assign(:errors, %{})
         |> assign(:check, %{status: :running, steps: pending, leftover: nil})
         |> start_async(:connection_check, fn -> check.(attrs, on_step: on_step) end)}
    end
  end

  @impl true
  def handle_async(:connection_check, {:ok, %{steps: steps} = result}, socket) do
    check = %{
      status: if(result.ok?, do: :passed, else: :failed),
      steps: Enum.map(steps, &described/1),
      leftover: result[:leftover]
    }

    {:noreply, assign(socket, :check, check)}
  end

  def handle_async(:connection_check, _other, socket) do
    steps =
      for step <- ConnectionCheck.steps(),
          do: described(%{step: step, status: :error, reason: :check_crashed})

    {:noreply, assign(socket, :check, %{status: :failed, steps: steps, leftover: nil})}
  end

  # A step as a host shows it: the status plus the words for it.
  defp described(step) do
    step = Map.put_new(step, :reason, nil)

    Map.merge(step, %{
      label: ConnectionCheck.label(step.step),
      detail: ConnectionCheck.detail(step)
    })
  end

  defp run_save(params, socket) do
    socket = assign(socket, :params, params) |> assign(:check, nil)
    attrs = normalize(params, socket.assigns.creds)

    case errors(attrs) do
      errors when map_size(errors) > 0 ->
        {:noreply, socket |> assign(:errors, errors) |> assign(:save_result, nil)}

      _ ->
        case S3Credentials.put(attrs, tenant_id: socket.assigns.tenant_id) do
          :ok ->
            broadcast_update(socket.assigns.tenant_id)

            {:noreply,
             socket
             |> assign(:errors, %{})
             |> assign(:creds, attrs)
             |> assign(:params, stored_params(attrs))
             |> assign(:save_result, :ok)}

          {:error, reason} ->
            {:noreply, socket |> assign(:errors, %{}) |> assign(:save_result, {:error, reason})}
        end
    end
  end

  # ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-6">
      <%!-- The host presents the check when it gives a `:check` slot; otherwise it is listed here. --%>
      <%= if @check && slot_given?(assigns) do %>
        {render_slot(@check_view, %{
          status: @check.status,
          steps: @check.steps,
          leftover: @check.leftover,
          target: @myself,
          dismiss: "dismiss_check"
        })}
      <% end %>
      <div
        :if={@check && not slot_given?(assigns)}
        id={"#{@id}-test-result"}
        role="status"
        class={["alert items-start", check_class(@check.status)]}
      >
        <div class="space-y-2">
          <p class="font-semibold">{check_title(@check.status)}</p>
          <ol class="space-y-1 text-sm">
            <li :for={step <- @check.steps} data-step={step.step} data-status={step.status}>
              <span aria-hidden="true">{step_mark(step.status)}</span>
              {step.label}: {step.detail}
            </li>
          </ol>
          <p :if={@check.leftover} class="text-sm">
            A test object could not be removed: <code>{@check.leftover}</code>
          </p>
        </div>
      </div>

      <div
        :if={@save_result}
        id={"#{@id}-save-result"}
        role="status"
        class={["alert", if(@save_result == :ok, do: "alert-success", else: "alert-error")]}
      >
        <%= if @save_result == :ok do %>
          <span>Credentials saved.</span>
        <% else %>
          <span><strong>Could not save</strong> — {humanize(@save_result)}</span>
        <% end %>
      </div>

      <form id="creds-form" phx-change="validate" phx-submit="save" phx-target={@myself} novalidate>
        <div class="space-y-4">
          <.field id="creds_access_key_id" name="access_key_id" label="Access Key ID" params={@params} errors={@errors} />
          <.field
            id="creds_secret_access_key"
            name="secret_access_key"
            label="Secret Access Key"
            type="password"
            params={@params}
            errors={@errors}
            hint={if secret_stored?(@creds), do: "A secret is saved. Leave blank to keep it."}
          />
          <.field id="creds_bucket" name="bucket" label="Bucket" params={@params} errors={@errors} />
          <.field
            id="creds_region"
            name="region"
            label="Region (optional)"
            params={@params}
            errors={@errors}
            hint="Leave blank for S3-compatible stores such as R2 or MinIO."
          />
          <.field
            id="creds_endpoint"
            name="endpoint"
            label="Endpoint URL"
            params={@params}
            errors={@errors}
            placeholder="https://..."
          />
        </div>

        <div class="mt-4 flex gap-3">
          <button
            type="submit"
            name="intent"
            value="test"
            id={"#{@id}-test"}
            class="btn btn-outline"
            disabled={@check != nil and @check.status == :running}
          >
            {if @check != nil and @check.status == :running, do: "Testing...", else: "Test Connection"}
          </button>
          <button type="submit" class="btn btn-primary" disabled={@saving?}>
            {if @saving?, do: "Saving...", else: "Save Credentials"}
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:type, :string, default: "text")
  attr(:params, :map, required: true)
  attr(:errors, :map, required: true)
  attr(:hint, :string, default: nil)
  attr(:placeholder, :string, default: nil)

  # A password input never gets a `value`: a secret is never rendered back into the HTML.
  defp field(assigns) do
    assigns = assign(assigns, :error, assigns.errors[assigns.name])

    ~H"""
    <div class="form-control w-full">
      <label for={@id} class="label"><span class="label-text font-medium">{@label}</span></label>
      <input
        type={@type}
        name={"creds[#{@name}]"}
        id={@id}
        value={if @type != "password", do: @params[@name]}
        placeholder={@placeholder}
        autocomplete={if @type == "password", do: "new-password", else: "off"}
        aria-invalid={@error && "true"}
        aria-describedby={@error && "#{@id}-error"}
        class={["input input-bordered w-full", @error && "input-error"]}
      />
      <p :if={@hint} class="label text-xs opacity-70">{@hint}</p>
      <p :if={@error} id={"#{@id}-error"} class="label text-sm text-error">{@error}</p>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp load_creds(tenant_id) do
    case S3Credentials.get(tenant_id: tenant_id) do
      {:ok, creds} -> creds
      _ -> %{}
    end
  end

  # Form values for a fresh render: everything but the secret, which is never echoed.
  defp stored_params(creds) do
    creds = creds || %{}

    Map.new(@fields -- ["secret_access_key"], fn k ->
      {k, to_string(Map.get(creds, String.to_existing_atom(k)) || "")}
    end)
  end

  # Only known string fields are kept, trimmed; anything else in the payload is dropped.
  defp clean_params(params) when is_map(params) do
    Map.new(@fields, fn k ->
      v = params[k]
      {k, if(is_binary(v), do: String.trim(v), else: "")}
    end)
  end

  # Blank secret keeps the stored one; blank region falls back to the S3 client default.
  defp normalize(params, stored) do
    stored = stored || %{}

    secret =
      case params["secret_access_key"] do
        v when v in [nil, ""] -> Map.get(stored, :secret_access_key) || ""
        v -> v
      end

    %{
      access_key_id: params["access_key_id"],
      secret_access_key: secret,
      bucket: params["bucket"],
      region: blank_to(params["region"], @default_region),
      endpoint: blank_to(params["endpoint"], nil)
    }
  end

  defp blank_to(v, default) when v in [nil, ""], do: default
  defp blank_to(v, _default), do: v

  defp errors(attrs) do
    for key <- @required, blank?(Map.get(attrs, String.to_existing_atom(key))), into: %{} do
      {key, "can't be blank"}
    end
  end

  defp blank?(v), do: v in [nil, ""]

  defp secret_stored?(creds), do: not blank?(Map.get(creds || %{}, :secret_access_key))

  # Reasons are atoms or short terms from this package; never the credentials themselves.
  defp slot_given?(assigns), do: assigns[:check_view] not in [nil, []]

  defp check_class(:passed), do: "alert-success"
  defp check_class(:failed), do: "alert-error"
  defp check_class(:running), do: nil

  defp check_title(:passed), do: "Connection verified: the store accepted every step."
  defp check_title(:failed), do: "Connection test failed."
  defp check_title(:running), do: "Testing the connection…"

  defp step_mark(:ok), do: "✓"
  defp step_mark(:error), do: "✗"
  defp step_mark(:skipped), do: "–"
  defp step_mark(:running), do: "…"
  defp step_mark(:pending), do: "·"

  defp humanize({:error, :missing_credentials}), do: "some credentials are missing"
  defp humanize({:error, reason}) when is_atom(reason), do: Phoenix.Naming.humanize(reason)
  defp humanize({:error, _reason}), do: "the request failed"

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
