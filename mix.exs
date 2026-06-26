defmodule Defdo.Uploader.MixProject do
  use Mix.Project

  @organization "defdo"
  @repo_url "https://github.com/defdo-dev/defdo_uploader"

  def project do
    [
      app: :defdo_uploader,
      version: version(),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp version do
    File.read!("VERSION") |> String.trim()
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:req_s3, "~> 0.4"},
      # Optional — tenancy
      {:defdo_tenant, "~> 0.10", optional: true, organization: @organization},
      # Optional — encrypted credential storage
      {:defdo_vault, "~> 0.9", optional: true, organization: @organization},
      # Optional — tenant-aware PubSub
      {:defdo_tenant_boundary, "~> 0.2", optional: true, organization: @organization},
      # Optional — LiveComponent form
      {:phoenix_live_view, ">= 1.0.0", optional: true},
      # Dev / Test
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "S3 operations, vault-backed credentials, and embeddable admin form. " <>
      "Tenant-aware via defdo_tenant (optional). Reusable across defdo_cms, defdo_notification_hub, defdo_theme_hub."
  end

  defp package do
    [
      organization: @organization,
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @repo_url,
        "Changelog" => "#{@repo_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
