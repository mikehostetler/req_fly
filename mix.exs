defmodule ReqFly.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/mikehostetler/req_fly"

  def project do
    [
      app: :req_fly,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: dialyzer()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/integration"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:exvcr, "~> 0.15", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.33", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Req plugin for the Fly.io Machines API"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv/openapi.json .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "ReqFly",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "doc/guides/GETTING_STARTED.md"
      ],
      groups_for_extras: [
        Guides: ~r/doc\/guides\/.*/
      ],
      groups_for_modules: [
        "High-level API": [
          ReqFly.Apps,
          ReqFly.Machines,
          ReqFly.Secrets,
          ReqFly.Volumes,
          ReqFly.Orchestrator
        ],
        Internal: [
          ReqFly.Steps,
          ReqFly.Error
        ]
      ],
      assets: %{"doc/assets" => "assets"},
      formatters: ["html"],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({ startOnLoad: false });
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""

  defp dialyzer do
    [
      plt_add_apps: [:mix],
      flags: [:unmatched_returns, :error_handling, :underspecs]
    ]
  end
end
