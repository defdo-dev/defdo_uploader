defmodule Defdo.Uploader.Key do
  @moduledoc """
  Object key layout for policy-managed assets.

      tenants/<tenant>/<kind>/<id>/<version>/<variant>.<ext>          owner: :tenant
      tenants/<tenant>/users/<id>/<kind>/<version>/<variant>.<ext>    owner: :user

  The tenant is part of every key, so a bucket listing, a lifecycle rule or an
  IAM policy can be scoped to one tenant, and a key built for one tenant can
  never address another's object.

  The tenant comes from `Defdo.Tenant.Context` when `defdo_tenant` is loaded.
  An explicit `:tenant_id` is accepted for system edges that run outside a
  request, but when both are present they must agree — a mismatch is an error,
  not a silent preference for either side.

  Every segment is validated rather than escaped: anything outside
  `[A-Za-z0-9_.-]`, anything starting with a dot, or anything containing `..`
  is rejected, so a caller-supplied id cannot introduce a path separator or
  traverse upwards.
  """

  alias Defdo.Uploader.Kind

  @segment ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/

  @doc """
  Builds the base key (everything before `/<variant>.<ext>`) for an object.

  Options:

    * `:id` (required) — the owning record, e.g. the user id for `:user_picture`
    * `:version` — defaults to a new time-ordered version
    * `:tenant_id` — see the moduledoc
    * `:key_prefix` — prepended as-is after validation, e.g. `"prod"`
  """
  @spec base(Kind.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def base(%Kind{} = kind, opts) do
    with {:ok, tenant} <- tenant(opts),
         {:ok, id} <- required_segment(opts, :id),
         {:ok, version} <- segment(Keyword.get_lazy(opts, :version, &new_version/0), :version),
         {:ok, prefix} <- prefix(opts[:key_prefix]) do
      kind_segment = Atom.to_string(kind.name)

      parts =
        case kind.owner do
          :user -> ["tenants", tenant, "users", id, kind_segment, version]
          :tenant -> ["tenants", tenant, kind_segment, id, version]
        end

      {:ok, Enum.join(prefix ++ parts, "/")}
    end
  end

  @doc "The key of one variant under a base key."
  @spec variant(String.t(), String.t(), :webp | :png | :jpeg) :: String.t()
  def variant(base, name, format), do: "#{base}/#{name}.#{extension(format)}"

  @doc "The file extension, without a dot, for an output format."
  @spec extension(:webp | :png | :jpeg) :: String.t()
  def extension(:webp), do: "webp"
  def extension(:png), do: "png"
  def extension(:jpeg), do: "jpg"

  @doc "A new version segment: sortable by time, unique within a millisecond."
  @spec new_version() :: String.t()
  def new_version do
    millis = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{millis}-#{random}"
  end

  defp tenant(opts) do
    explicit = opts[:tenant_id]
    context = context_tenant()

    cond do
      present?(explicit) and present?(context) and to_string(explicit) != to_string(context) ->
        {:error, :tenant_mismatch}

      present?(context) ->
        segment(context, :tenant_id)

      present?(explicit) ->
        segment(explicit, :tenant_id)

      true ->
        {:error, :tenant_required}
    end
  end

  defp context_tenant do
    context = Defdo.Tenant.Context

    if Code.ensure_loaded?(context) and function_exported?(context, :tenant_id, 0) do
      context.tenant_id()
    end
  end

  defp required_segment(opts, name) do
    case opts[name] do
      value when value in [nil, ""] -> {:error, {:missing, name}}
      value -> segment(value, name)
    end
  end

  defp segment(value, name) do
    value = to_string(value)

    if Regex.match?(@segment, value) and not String.contains?(value, "..") do
      {:ok, value}
    else
      {:error, {:invalid_segment, name}}
    end
  end

  defp prefix(nil), do: {:ok, []}
  defp prefix(""), do: {:ok, []}

  defp prefix(prefix) when is_binary(prefix) do
    prefix
    |> String.trim("/")
    |> String.split("/")
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case segment(part, :key_prefix) do
        {:ok, part} -> {:cont, {:ok, acc ++ [part]}}
        error -> {:halt, error}
      end
    end)
  end

  defp prefix(_other), do: {:error, {:invalid_segment, :key_prefix}}

  defp present?(value), do: value not in [nil, ""]
end
