defmodule PhoenixTestOnly do
  @moduledoc """
  Test sandbox orchestration for Phoenix apps.

  Automatically emits all plugs and hooks declared by configured sandbox
  adapters. Nothing to maintain — add an adapter to config and the plugs
  and hooks appear.

      # endpoint.ex
      import PhoenixTestOnly
      sandbox_plugs()

      # your_app_web.ex live_view macro
      import PhoenixTestOnly
      sandbox_on_mount()

  Outside test env (`Mix.env() != :test` or Mix not loaded), both macros
  emit nothing.
  """

  @doc """
  Emits `plug(mod)` for every plug declared by configured sandbox adapters.
  Emits nothing outside test env.
  """
  defmacro sandbox_plugs do
    if test_env?() do
      for mod <- PhoenixTestOnly.Sandbox.collect_plugs() do
        quote do: plug(unquote(mod))
      end
    end
  end

  @doc """
  Emits `on_mount(mod)` for every hook declared by configured sandbox adapters.
  Emits nothing outside test env.
  """
  defmacro sandbox_on_mount do
    if test_env?() do
      for mod <- PhoenixTestOnly.Sandbox.collect_hooks() do
        quote do: on_mount(unquote(mod))
      end
    end
  end

  @doc false
  def test_env? do
    function_exported?(Mix, :env, 0) and Mix.env() == :test
  end
end
