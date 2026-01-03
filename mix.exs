defmodule Yex.MixProject do
  use Mix.Project

  def project do
    [
      app: :yex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:finger_tree, git: "https://github.com/point/finger_tree.git", branch: "partial_order"}
    ]
  end
end
