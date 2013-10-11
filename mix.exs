defmodule ElixirPipes.Mixfile do
  use Mix.Project

  def project do
    [ app: :elixir_pipes,
      version: "0.0.1",
      elixir: "~> 0.10.3-dev",
      deps: deps,
      docs: [ main: Pipe, source_url: "https://github.com/pminten/elixir_pipes/", readme: true ] ]
  end

  # Configuration for the OTP application
  def application do
    []
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "~> 0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    []
  end
end
