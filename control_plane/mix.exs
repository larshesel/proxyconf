defmodule ProxyConf.MixProject do
  use Mix.Project

  def project do
    [
      app: :proxyconf,
      version: "0.1.0",
      build_path: "../_build",
      config_path: "config/config.exs",
      deps_path: "../deps",
      lockfile: "mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps(),
      aliases: aliases(),
      compilers: [:yecc] ++ Mix.compilers(),
      test_coverage: [
        ignore_modules: [
          Jason.Encoder.URI,
          Mix.Tasks.GenMarkdown,
          Inspect.ProxyConf.Commons.MapTemplate
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ProxyConf.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def releases do
    [
      proxyconf: [
        included_executables: [:unix],
        applications: [proxyconf: :permanent, runtime_tools: :permanent]
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dotenvy, "~> 0.9.0"},
      {:proxyconf_commons, path: "../commons"},
      ######################################################
      # Phoenix Deps
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      # TODO bump on release to {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_live_view, "~> 1.0.0", override: true},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      # used for phoenix live dashboard
      {:ecto_psql_extras, "~> 0.6"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:dns_cluster, "~> 0.1.1"},
      {:argon2_elixir, "~> 4.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:cloak_ecto, "~> 1.2.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      ######################################################
      # ProxyConf Deps
      {:ex_oauth2_provider, "~> 0.5.7"},
      {:plug_cowboy, "~> 2.7"},
      {:joken, "~> 2.6"},
      #      {:proxyconf_validator, path: "../proxyconf_validator", optional: true},
      {:x509, "~> 0.8.9"},
      {:credo, "~> 1.7", only: [:test, :dev], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind proxyconf", "esbuild proxyconf"],
      "assets.deploy": [
        "tailwind proxyconf --minify",
        "esbuild proxyconf --minify",
        "phx.digest"
      ]
    ]
  end
end
