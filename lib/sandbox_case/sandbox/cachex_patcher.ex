defmodule SandboxCase.Sandbox.CachexPatcher do
  @moduledoc false
  # Patches Cachex.Services.Overseer.retrieve/1 at runtime to check the
  # process dictionary (and $callers) for sandbox overrides. This allows
  # sandbox_case to work with vanilla Cachex (no fork required).

  @target Cachex.Services.Overseer

  @doc false
  def patch! do
    cond do
      not Code.ensure_loaded?(@target) ->
        :not_loaded

      already_patched?() ->
        :already_patched

      expected_vanilla?() ->
        do_patch()

      true ->
        require Logger

        Logger.warning(
          "SandboxCase: Cachex.Services.Overseer doesn't match expected shape. " <>
            "Cachex sandbox patching skipped. " <>
            "Expected vanilla Cachex ~> 4.1 or an already-patched module."
        )

        :unexpected_shape
    end
  end

  # Our patch includes find_sandbox_in_callers — check for it
  defp already_patched? do
    source = get_beam_source()
    source != nil and String.contains?(source, "find_sandbox_in_callers")
  end

  # Vanilla Cachex has retrieve/1 with a direct ETS lookup, no sandbox logic
  defp expected_vanilla? do
    exports = @target.__info__(:functions)
    {:retrieve, 1} in exports and not has_sandbox_logic?()
  end

  defp has_sandbox_logic? do
    source = get_beam_source()
    source != nil and String.contains?(source, "cachex_sandbox")
  end

  defp get_beam_source do
    case :code.get_object_code(@target) do
      {_, beam, _} ->
        case :beam_lib.chunks(beam, [:abstract_code]) do
          {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} ->
            inspect(forms)

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp do_patch do
    Code.compiler_options(ignore_module_conflict: true)

    Module.create(
      @target,
      patched_module_ast(),
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

  defp patched_module_ast do
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

      def retrieve(name) do
        resolved = find_sandbox(name)

        case :ets.lookup(@table_name, resolved) do
          [{^resolved, state}] -> state
          _other -> nil
        end
      end

      defp find_sandbox(name) do
        case Process.get({:cachex_sandbox, name}) do
          nil -> find_sandbox_in_callers(name, Process.get(:"$callers") || [])
          instance -> instance
        end
      end

      defp find_sandbox_in_callers(name, []), do: name

      defp find_sandbox_in_callers(name, [pid | rest]) do
        case :erlang.process_info(pid, :dictionary) do
          {:dictionary, dict} ->
            case List.keyfind(dict, {:cachex_sandbox, name}, 0) do
              {{:cachex_sandbox, ^name}, instance} -> instance
              _ -> find_sandbox_in_callers(name, rest)
            end

          _ ->
            find_sandbox_in_callers(name, rest)
        end
      catch
        _, _ -> find_sandbox_in_callers(name, rest)
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
    end
  end
end
