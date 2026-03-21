defmodule SandboxCase.Sandbox.CachexPatcher do
  @moduledoc false
  # Patches Cachex.Services.Overseer.retrieve/1 at runtime to check the
  # process dictionary for sandbox overrides. This allows sandbox_case
  # to work with vanilla Cachex (no fork required).
  #
  # Only patches if retrieve/1 matches the expected implementation.
  # If Cachex changes the function, we warn instead of silently breaking.

  @target Cachex.Services.Overseer

  @doc false
  def patch! do
    cond do
      not Code.ensure_loaded?(@target) ->
        :not_loaded

      already_patched?() ->
        :already_patched

      not expected_shape?() ->
        require Logger

        Logger.warning(
          "SandboxCase: Cachex.Services.Overseer doesn't match expected shape. " <>
            "Cachex sandbox patching skipped — cache isolation may not work. " <>
            "Consider using the pinetops/cachex fork or updating sandbox_case."
        )

        :unexpected_shape

      true ->
        do_patch()
    end
  end

  # Check if retrieve/1 already has our sandbox logic
  defp already_patched? do
    Process.put({:cachex_sandbox, :__patch_test__}, :__patched__)

    result =
      try do
        # If patched, retrieve(:__patch_test__) resolves to :__patched__
        # which won't be in the ETS table, so returns nil.
        # If unpatched, it also returns nil but via direct ETS lookup.
        # We can't distinguish — instead check the beam for our marker.
        source = get_beam_source()
        source != nil and String.contains?(source, "cachex_sandbox")
      rescue
        _ -> false
      end

    Process.delete({:cachex_sandbox, :__patch_test__})
    result
  end

  # Verify the module has the functions we expect to replace
  defp expected_shape? do
    exports = @target.__info__(:functions)

    expected = [
      {:retrieve, 1},
      {:get, 1},
      {:known?, 1},
      {:register, 2},
      {:start_link, 0},
      {:started?, 0},
      {:transaction, 2},
      {:unregister, 1},
      {:update, 2},
      {:with, 2}
    ]

    Enum.all?(expected, &(&1 in exports)) and verify_retrieve_source()
  end

  # Verify retrieve/1 does what we expect: an ETS lookup on the name directly
  defp verify_retrieve_source do
    case get_beam_source() do
      nil ->
        # No source available — check by behaviour instead
        # retrieve/1 should return nil for unknown names
        @target.retrieve(:__nonexistent_cache_name__) == nil

      source ->
        # The vanilla retrieve/1 should contain :ets.lookup and @table_name
        String.contains?(source, "ets.lookup") and
          String.contains?(source, "cachex_overseer_table")
    end
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

      # PATCHED: check process dictionary for sandbox override
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
    end
  end
end
