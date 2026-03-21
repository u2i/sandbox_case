defmodule SandboxCase do
  @moduledoc """
  Batteries-included test isolation for Elixir and Phoenix.

  Use `SandboxShim` for compile-time macros (endpoint/LiveView wiring).
  Use `SandboxCase.Sandbox` for runtime setup/checkout/checkin.

  ## Quick start

      # mix.exs
      {:sandbox_shim, "~> 0.1"},                   # all envs
      {:sandbox_case, "~> 0.3", only: :test},      # test only

      # test/test_helper.exs
      SandboxCase.Sandbox.setup()

      # test modules
      use SandboxCase.Sandbox.Case
  """
end
