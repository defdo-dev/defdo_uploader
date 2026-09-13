defmodule Defdo.Uploader.Kind do
  @moduledoc """
  A storage policy for one kind of uploaded asset.

  A kind answers every question an upload raises before any byte reaches a
  bucket: who owns the object, whether anyone may read it without a
  signature, which content types are acceptable, how large the upload and its
  decoded pixel grid may be, and which rendered variants are stored.

  ## Built-in kinds

  | Kind | Owner | Visibility | Variants |
  |---|---|---|---|
  | `:tenant_logo` | tenant | public | `display` WebP 1024, `fallback` PNG 1024 |
  | `:tenant_background` | tenant | public | `display` WebP 2560, `fallback` JPEG 2560 |
  | `:user_picture` | user | private | `display` WebP 512, `fallback` JPEG 512 |
  | `:platform_icon` | tenant | public | `original` PNG, never WebP |

  Each web-facing kind stores a WebP variant for browsers and a PNG or JPEG
  fallback. The fallback exists because some consumers cannot decode WebP:
  Outlook renders images in email without it, and relying parties may show an
  OIDC `picture` in a native app. `:platform_icon` has no WebP variant at all
  because the platforms that consume icons — iOS app icons, `apple-touch-icon`,
  Play Store listings, favicons and PWA manifests — require or strongly prefer
  PNG.

  ## SVG

  SVG is rejected unless a kind sets `allow_svg: true`, because an SVG is a
  document that can carry script. When allowed, it is **rasterised** into the
  kind's variants and the SVG source itself is never stored.

  ## Overriding

      config :defdo_uploader, :kinds, %{
        tenant_logo: [max_bytes: 2_000_000],
        product_photo: [owner: :tenant, visibility: :public, variants: [...]]
      }

  Entries are merged over the built-in kind of the same name, or define a new
  kind when no built-in exists.
  """

  @type variant :: %{
          required(:name) => String.t(),
          required(:format) => :webp | :png | :jpeg,
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer(),
          optional(:fit) => :contain | :cover,
          optional(:quality) => 1..100
        }

  @type t :: %__MODULE__{
          name: atom(),
          owner: :tenant | :user,
          visibility: :public | :private,
          accept: [String.t()],
          allow_svg: boolean(),
          max_bytes: pos_integer(),
          max_pixels: pos_integer(),
          cache_control: String.t(),
          variants: [variant()]
        }

  @enforce_keys [:name]
  defstruct name: nil,
            owner: :tenant,
            visibility: :private,
            accept: ["image/png", "image/jpeg", "image/webp"],
            allow_svg: false,
            max_bytes: 5_000_000,
            # Guards against decompression bombs: a few kilobytes of PNG can
            # declare a pixel grid that exhausts memory once decoded.
            max_pixels: 40_000_000,
            cache_control: "private, max-age=300",
            variants: []

  # Keys carry a version segment, so a public object never changes after it
  # is written and can be cached for a year.
  @immutable "public, max-age=31536000, immutable"

  @builtin %{
    tenant_logo: [
      owner: :tenant,
      visibility: :public,
      accept: ["image/png", "image/jpeg", "image/webp", "image/svg+xml"],
      allow_svg: true,
      cache_control: @immutable,
      variants: [
        %{name: "display", format: :webp, width: 1024, height: 1024, fit: :contain, quality: 90},
        %{name: "fallback", format: :png, width: 1024, height: 1024, fit: :contain}
      ]
    ],
    tenant_background: [
      owner: :tenant,
      visibility: :public,
      max_bytes: 10_000_000,
      cache_control: @immutable,
      variants: [
        %{name: "display", format: :webp, width: 2560, height: 2560, fit: :contain, quality: 80},
        %{name: "fallback", format: :jpeg, width: 2560, height: 2560, fit: :contain, quality: 82}
      ]
    ],
    user_picture: [
      owner: :user,
      visibility: :private,
      cache_control: "private, max-age=300",
      variants: [
        %{name: "display", format: :webp, width: 512, height: 512, fit: :cover, quality: 82},
        %{name: "fallback", format: :jpeg, width: 512, height: 512, fit: :cover, quality: 85}
      ]
    ],
    platform_icon: [
      owner: :tenant,
      visibility: :public,
      accept: ["image/png", "image/jpeg", "image/webp", "image/svg+xml"],
      allow_svg: true,
      cache_control: @immutable,
      variants: [%{name: "original", format: :png}]
    ]
  }

  @doc "Names of the kinds available, built-in and configured."
  @spec names() :: [atom()]
  def names do
    @builtin
    |> Map.merge(configured(), fn _name, builtin, _override -> builtin end)
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Resolves a kind by name, applying any `config :defdo_uploader, :kinds` entry.
  """
  @spec fetch(atom() | t()) :: {:ok, t()} | {:error, {:unknown_kind, term()}}
  def fetch(%__MODULE__{} = kind), do: {:ok, kind}

  def fetch(name) when is_atom(name) do
    case {Map.get(@builtin, name), Map.get(configured(), name)} do
      {nil, nil} -> {:error, {:unknown_kind, name}}
      {builtin, override} -> {:ok, build(name, Keyword.merge(builtin || [], override || []))}
    end
  end

  def fetch(other), do: {:error, {:unknown_kind, other}}

  @doc "Whether objects of this kind may be read without a signature."
  @spec public?(t()) :: boolean()
  def public?(%__MODULE__{visibility: visibility}), do: visibility == :public

  defp build(name, fields) do
    struct!(__MODULE__, Keyword.put(fields, :name, name))
  end

  defp configured do
    :defdo_uploader
    |> Application.get_env(:kinds, %{})
    |> Map.new(fn {name, fields} -> {name, Enum.to_list(fields)} end)
  end
end
