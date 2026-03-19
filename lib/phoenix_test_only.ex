defmodule PhoenixTestOnly do
  @moduledoc """
  Test sandbox orchestration and compile-time conditional `plug`/`on_mount`
  for Phoenix apps.

  ## Zero-arg macros (recommended)

  Automatically emit all plugs and hooks declared by configured sandbox
  adapters. Nothing to maintain — add an adapter to config and the plugs
  and hooks appear.

      # endpoint.ex
      import PhoenixTestOnly
      sandbox_plugs()

      # your_app_web.ex live_view macro
      import PhoenixTestOnly
      sandbox_on_mount()

  ## Explicit macros

  For manual control, `plug_if_test` and `on_mount_if_test` emit a single
  plug/hook only when `Mix.env() == :test`.

      plug_if_test Phoenix.Ecto.SQL.Sandbox
      on_mount_if_test Wallabidi.Sandbox.Hook
  """

  @doc """
  Emits `plug(mod)` for every plug declared by configured sandbox adapters.
  Emits nothing outside test env.

  ## Example

      # endpoint.ex
      import PhoenixTestOnly
      sandbox_plugs()
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

  ## Example

      # your_app_web.ex
      def live_view do
        quote do
          use Phoenix.LiveView
          import PhoenixTestOnly
          sandbox_on_mount()
        end
      end
  """
  defmacro sandbox_on_mount do
    if test_env?() do
      for mod <- PhoenixTestOnly.Sandbox.collect_hooks() do
        quote do: on_mount(unquote(mod))
      end
    end
  end

  @doc """
  Emits `plug(module)` if compiling in test env and the module is loaded;
  otherwise nothing.
  """
  defmacro plug_if_test(module, opts \\ []) do
    module = Macro.expand(module, __CALLER__)

    if test_env?() and Code.ensure_loaded?(module) do
      if opts == [] do
        quote do: plug(unquote(module))
      else
        quote do: plug(unquote(module), unquote(opts))
      end
    end
  end

  @doc """
  Emits `on_mount(module)` if compiling in test env and the module is loaded;
  otherwise nothing.
  """
  defmacro on_mount_if_test(module, _opts \\ []) do
    module = Macro.expand(module, __CALLER__)

    if test_env?() and Code.ensure_loaded?(module) do
      quote do: on_mount(unquote(module))
    end
  end

  @doc false
  def test_env? do
    function_exported?(Mix, :env, 0) and Mix.env() == :test
  end
end
