defmodule Defdo.Uploader.ConnectionCheck do
  @moduledoc """
  Proves a set of S3-compatible credentials end to end, with one throwaway object.

  Four steps, in order, each a real request to the store:

    1. `:connect` — the bucket answers and accepts the signature (a HEAD for the
       probe key must say "not found");
    2. `:write`   — put the probe object and read the same bytes back;
    3. `:edit`    — overwrite it and read the new bytes back;
    4. `:delete`  — delete it and confirm it is gone.

  A step that fails stops the run; the steps after it are `:skipped`. Whatever
  happens, the probe object is removed: when the run stops after a write, the
  delete is still attempted and a leftover is reported in `:leftover`.

  The probe key is random and lives under `.defdo-connection-check/` inside the
  bucket's prefix, so it can never be an object the tenant owns. Nothing here
  logs, and a reason is an atom or an HTTP status: never a credential.
  """

  alias Defdo.Uploader.Adapters.S3

  @steps [:connect, :write, :edit, :delete]
  @folder ".defdo-connection-check"

  @type step :: %{step: atom(), status: :ok | :error | :skipped, reason: term()}
  @type result :: %{ok?: boolean(), steps: [step()], leftover: String.t() | nil}

  @doc "The steps, in the order they run."
  def steps, do: @steps

  @spec run(map()) :: result()
  def run(config) when is_map(config) do
    config = with_timeouts(config)
    key = probe_key(config)

    steps =
      @steps
      |> Enum.reduce([], fn step, done ->
        if Enum.any?(done, &(&1.status != :ok)) do
          [%{step: step, status: :skipped, reason: nil} | done]
        else
          case run_step(step, key, config) do
            :ok -> [%{step: step, status: :ok, reason: nil} | done]
            {:error, reason} -> [%{step: step, status: :error, reason: public(reason)} | done]
          end
        end
      end)
      |> Enum.reverse()

    ok? = Enum.all?(steps, &(&1.status == :ok))

    %{ok?: ok?, steps: steps, leftover: leftover(ok?, steps, key, config)}
  end

  defp run_step(:connect, key, config) do
    case S3.head_object(key, config) do
      {:error, :not_found} -> :ok
      # A random key that exists would be a collision; treat the store as reachable.
      {:ok, _meta} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_step(:write, key, config), do: put_and_read(key, "defdo connection check 1", config)
  defp run_step(:edit, key, config), do: put_and_read(key, "defdo connection check 2", config)

  defp run_step(:delete, key, config) do
    with :ok <- S3.delete_object(key, config) do
      case S3.head_object(key, config) do
        {:error, :not_found} -> :ok
        {:ok, _meta} -> {:error, :still_there}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp put_and_read(key, body, config) do
    with :ok <- S3.put_object(key, body, "text/plain", config),
         {:ok, %{body: read}} <- S3.get_object(key, config) do
      if read == body, do: :ok, else: {:error, :content_mismatch}
    end
  end

  # A run that stopped after the connect step may have written the object,
  # even when the write step itself is the one that failed (the bytes arrived
  # but did not read back). The delete is idempotent, so it is always tried;
  # the key is reported only when the store refuses it.
  defp leftover(true, _steps, _key, _config), do: nil

  defp leftover(false, [%{step: :connect, status: status} | _], _key, _config) when status != :ok,
    do: nil

  defp leftover(false, _steps, key, config) do
    case S3.delete_object(key, config) do
      :ok -> nil
      _error -> key
    end
  end

  defp probe_key(config) do
    name = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

    case S3.bucket_and_prefix(Map.get(config, :bucket)) do
      {_bucket, prefix} when is_binary(prefix) and prefix != "" ->
        Enum.join([String.trim(prefix, "/"), @folder, name <> ".txt"], "/")

      _ ->
        Enum.join([@folder, name <> ".txt"], "/")
    end
  end

  # A wrong endpoint must fail in seconds, not hold the page for a minute.
  defp with_timeouts(config) do
    defaults = [retry: false, receive_timeout: 8_000, connect_options: [timeout: 5_000]]
    Map.put(config, :req_options, Keyword.merge(defaults, Map.get(config, :req_options) || []))
  end

  # Only shapes that cannot carry a credential leave this module.
  defp public(reason) when is_atom(reason), do: reason
  defp public({:http_status, status}) when is_integer(status), do: {:http_status, status}
  defp public(%{__exception__: true} = error), do: {:transport, error.__struct__}
  defp public(_other), do: :request_failed
end
