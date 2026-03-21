defmodule SandboxCase.Sandbox.CachexPatcher do
  @moduledoc false
  # Patches Cachex.Services.Overseer.retrieve/1 at runtime to check the
  # process dictionary for sandbox overrides. This allows sandbox_case
  # to work with vanilla Cachex (no fork required).
  #
  # The patch is applied once in setup/1 and is VM-global — it affects
  # all calls to Cachex in the test VM.

  @target Cachex.Services.Overseer

  def patch! do
    if Code.ensure_loaded?(@target) and not already_patched?() do
      do_patch()
    end
  end

  defp already_patched? do
    # Check if retrieve/1 already has our sandbox check
    # by calling it with a known process dict entry
    Process.put({:cachex_sandbox, :__patch_test__}, :__patched__)

    result =
      try do
        @target.retrieve(:__patch_test__) == nil
      rescue
        _ -> true
      end

    Process.delete({:cachex_sandbox, :__patch_test__})
    not result
  end

  defp do_patch do
    # Redefine the module with the patched retrieve/1
    Code.compiler_options(ignore_module_conflict: true)

    Module.create(
      @target,
      quote do
        @moduledoc false
        import Cachex.Spec

        @table_name :cachex_overseer_table
        @manager_name :cachex_overseer_manager

        def start_link do
          ets_opts = [read_concurrency: true, write_concurrency: true]
          tab_opts = [@table_name, ets_opts, [quiet: true]]
          mgr_opts = [1, [name: @manager_name]]

          children = [
            %{id: :sleeplocks, start: {:sleeplocks, :start_link, mgr_opts}},
            %{id: Eternal, start: {Eternal, :start_link, tab_opts}, type: :supervisor}
          ]

          Supervisor.start_link(children,
            strategy: :one_for_one,
            name: :cachex_overseer
          )
        end

        def get(cache() = cache), do: cache
        def get(name) when is_atom(name), do: retrieve(name)
        def get(_miss), do: nil

        def known?(name) when is_atom(name),
          do: :ets.member(@table_name, name)

        def register(name, cache() = cache) when is_atom(name),
          do: :ets.insert(@table_name, {name, cache})

        # THE PATCH: check process dictionary for sandbox override
        def retrieve(name) do
          resolved = Process.get({:cachex_sandbox, name}, name)

          case :ets.lookup(@table_name, resolved) do
            [{^resolved, state}] -> state
            _other -> nil
          end
        end

        def started?,
          do: Enum.member?(:ets.all(), @table_name)

        def transaction(name, fun) when is_atom(name) and is_function(fun, 0),
          do: :sleeplocks.execute(@manager_name, fun)

        def unregister(name) when is_atom(name),
          do: :ets.delete(@table_name, name)

        def update(name, fun) when is_atom(name) and is_function(fun, 1) do
          transaction(name, fn ->
            cstate = retrieve(name)
            nstate = fun.(cstate)
            register(name, nstate)
            Cachex.Services.Steward.provide(nstate, {:cache, nstate})
            nstate
          end)
        end

        def update(name, cache(name: name) = cache),
          do: update(name, fn _ -> cache end)

        def with(cache, handler) do
          case __MODULE__.get(cache) do
            nil ->
              {:error, :no_cache}

            cache(name: name) = cache ->
              if :erlang.whereis(name) != :undefined do
                handler.(cache)
              else
                {:error, :no_cache}
              end
          end
        end
      end,
      Macro.Env.location(__ENV__)
    )

    Code.compiler_options(ignore_module_conflict: false)
    :ok
  rescue
    e ->
      require Logger
      Logger.warning("SandboxCase: failed to patch Cachex Overseer: #{Exception.message(e)}")
      :error
  end
end
