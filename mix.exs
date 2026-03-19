defmodule SandboxCase.MixProject do
  use Mix.Project

  @source_url "https://github.com/pinetops/sandbox_case"
  @version "0.1.1"

  def project do
    [
      app: :sandbox_case,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: "Batteries-included test isolation for Elixir and Phoenix.",
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:plug, "~> 1.14", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:phoenix_ecto, "~> 4.0", optional: true},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Tom Clarke"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      extras: ["README.md": [title: "Introduction"]],
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "readme"
    ]
  end
end
