defmodule SandboxCase.Sandbox.FwfAdapter do
  @moduledoc """
  A sandbox-aware `FunWithFlags.Store.Persistent` adapter.

  This is the no-bytecode-patching replacement for `FwfPatcher`. It is a
  normal FunWithFlags persistence adapter (a documented extension point):
  on every flag operation it checks the process dictionary (and `$callers`)
  for a `:fwf_sandbox` ETS table. When one is present — i.e. inside a
  sandboxed test — reads and writes route to that isolated table (via
  `FwfStore`). When absent, it delegates to the project's real persistence
  adapter, so production/non-sandboxed code paths are unchanged.

  ## Configuration

      config :fun_with_flags, :persistence,
        adapter: SandboxCase.Sandbox.FwfAdapter,
        sandbox_real_adapter: FunWithFlags.Store.Persistent.Ecto,
        repo: MyApp.Repo            # opts for the real adapter, passed through

      # The FunWithFlags cache must be off so every lookup reaches the
      # (sandbox-aware) store rather than a shared global ETS cache:
      config :fun_with_flags, :cache, enabled: false

  `:sandbox_real_adapter` is the adapter to use when NOT sandboxed; it
  must be a different module than this one (otherwise lookups would
  recurse). All other keys under `:persistence` are read by the real
  adapter as usual.
  """
  # `fun_with_flags` is an `only: :test` dependency, so the behaviour
  # module isn't loaded when this file compiles in :dev/:prod. Declare the
  # behaviour only when it's available — conformance is still checked in
  # :test (where the adapter is actually used) without warning elsewhere.
  if Code.ensure_loaded?(FunWithFlags.Store.Persistent) do
    @behaviour FunWithFlags.Store.Persistent
  end

  alias SandboxCase.Sandbox.FwfStore

  def worker_spec do
    # The sandbox ETS tables are owned by SandboxCase.Sandbox.FunWithFlags's
    # pool, not by the persistence layer. Delegate the real adapter's
    # worker (e.g. the Ecto repo is supervised by the host app already, so
    # this is typically nil) so non-sandboxed operation is unaffected.
    real_adapter().worker_spec()
  end

  def get(flag_name) do
    case sandbox_table() do
      nil -> real_adapter().get(flag_name)
      table -> FwfStore.lookup(table, flag_name)
    end
  end

  def put(flag_name, gate) do
    case sandbox_table() do
      nil -> real_adapter().put(flag_name, gate)
      table -> FwfStore.put(table, flag_name, gate)
    end
  end

  def delete(flag_name, gate) do
    case sandbox_table() do
      nil -> real_adapter().delete(flag_name, gate)
      table -> FwfStore.delete(table, flag_name, gate)
    end
  end

  def delete(flag_name) do
    case sandbox_table() do
      nil -> real_adapter().delete(flag_name)
      table -> FwfStore.delete(table, flag_name)
    end
  end

  def all_flags do
    case sandbox_table() do
      nil -> real_adapter().all_flags()
      table -> FwfStore.all_flags(table)
    end
  end

  def all_flag_names do
    case sandbox_table() do
      nil -> real_adapter().all_flag_names()
      table -> FwfStore.all_flag_names(table)
    end
  end

  # The real persistence adapter to delegate to when not sandboxed.
  defp real_adapter do
    persistence = Application.get_env(:fun_with_flags, :persistence, [])

    case Keyword.get(persistence, :sandbox_real_adapter) do
      nil ->
        raise """
        SandboxCase.Sandbox.FwfAdapter requires the real persistence adapter \
        to delegate to. Configure it:

            config :fun_with_flags, :persistence,
              adapter: SandboxCase.Sandbox.FwfAdapter,
              sandbox_real_adapter: FunWithFlags.Store.Persistent.Ecto,
              repo: MyApp.Repo
        """

      __MODULE__ ->
        raise "sandbox_real_adapter must differ from SandboxCase.Sandbox.FwfAdapter (would recurse)"

      adapter ->
        adapter
    end
  end

  # The isolated ETS table for the current test, found directly in the
  # process dictionary or via the `$callers` chain (so flags set from a
  # spawned Task / LiveView still resolve to the right sandbox).
  defp sandbox_table do
    case Process.get(:fwf_sandbox) do
      nil -> find_in_callers(Process.get(:"$callers") || [])
      table -> table
    end
  end

  defp find_in_callers([]), do: nil

  defp find_in_callers([pid | rest]) do
    case :erlang.process_info(pid, :dictionary) do
      {:dictionary, dict} ->
        case List.keyfind(dict, :fwf_sandbox, 0) do
          {:fwf_sandbox, table} -> table
          _ -> find_in_callers(rest)
        end

      _ ->
        find_in_callers(rest)
    end
  catch
    _, _ -> find_in_callers(rest)
  end
end
