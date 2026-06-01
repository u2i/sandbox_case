defmodule SandboxCase.Sandbox.FunWithFlags do
  @moduledoc """
  Sandbox adapter for FunWithFlags. Works with vanilla FunWithFlags — no
  fork and no bytecode patching.

  Isolation is provided by a custom persistence adapter,
  `SandboxCase.Sandbox.FwfAdapter`, which routes flag operations to an
  isolated per-test ETS table when a `:fwf_sandbox` marker is present in
  the process dictionary (or reachable via `$callers`), and delegates to
  the real adapter otherwise. This module manages the pool of ETS tables
  and the per-test checkout/checkin.

      config :sandbox_case,
        sandbox: [fun_with_flags: true]

  The host app must point FunWithFlags at the sandbox adapter and disable
  the cache in the test environment:

      config :fun_with_flags, :persistence,
        adapter: SandboxCase.Sandbox.FwfAdapter,
        sandbox_real_adapter: FunWithFlags.Store.Persistent.Ecto,
        repo: MyApp.Repo

      config :fun_with_flags, :cache, enabled: false

  `setup/1` validates this wiring and raises with guidance if it's missing
  or wrong, rather than letting flag isolation silently leak.
  """
  @behaviour SandboxCase.Sandbox.Adapter
  use GenServer

  @impl true
  def available? do
    Code.ensure_loaded?(FunWithFlags)
  end

  @impl true
  def setup(config) do
    validate_config!()

    pool_size =
      case config do
        c when is_list(c) -> Keyword.get(c, :pool_size, System.schedulers_online())
        _ -> System.schedulers_online()
      end

    # Start the pool
    {:ok, _} = GenServer.start_link(__MODULE__, pool_size, name: __MODULE__)
    :ok
  end

  # Verify the host app wired FunWithFlags for sandboxing. These are
  # mistakes that otherwise manifest as silently-leaked flag state across
  # async tests (or a confusing boot crash), so we fail loudly here.
  defp validate_config! do
    persistence = Application.get_env(:fun_with_flags, :persistence, [])
    adapter = Keyword.get(persistence, :adapter)
    real = Keyword.get(persistence, :sandbox_real_adapter)
    cache_enabled = Keyword.get(Application.get_env(:fun_with_flags, :cache, []), :enabled, true)

    cond do
      adapter != SandboxCase.Sandbox.FwfAdapter ->
        raise """
        sandbox_case: FunWithFlags isolation requires the sandbox persistence adapter.

        Configure (typically in config/test.exs):

            config :fun_with_flags, :persistence,
              adapter: SandboxCase.Sandbox.FwfAdapter,
              sandbox_real_adapter: FunWithFlags.Store.Persistent.Ecto,
              repo: MyApp.Repo

        Found adapter: #{inspect(adapter)}
        """

      is_nil(real) or real == SandboxCase.Sandbox.FwfAdapter ->
        raise """
        sandbox_case: set `:sandbox_real_adapter` to the adapter to use when
        not sandboxed (it must differ from SandboxCase.Sandbox.FwfAdapter):

            config :fun_with_flags, :persistence,
              adapter: SandboxCase.Sandbox.FwfAdapter,
              sandbox_real_adapter: FunWithFlags.Store.Persistent.Ecto,
              repo: MyApp.Repo

        Found sandbox_real_adapter: #{inspect(real)}
        """

      cache_enabled ->
        raise """
        sandbox_case: disable the FunWithFlags cache in the test environment.

        FunWithFlags keeps a single global ETS read-cache in front of the
        store; with it enabled, one test's flag value can be served to
        another concurrent test from that shared cache, bypassing the
        sandbox. Set (compile-time, in config/test.exs):

            config :fun_with_flags, :cache, enabled: false
        """

      true ->
        :ok
    end
  end

  @impl true
  def propagate_keys(_config), do: [:fwf_sandbox]

  @impl true
  def checkout(config) do
    if Process.whereis(__MODULE__) do
      table = GenServer.call(__MODULE__, :checkout)
      Process.put(:fwf_sandbox, table)

      # Pre-seed flags if configured
      flags =
        case config do
          c when is_list(c) -> Keyword.get(c, :flags, [])
          _ -> []
        end

      gate_mod = Module.concat([FunWithFlags, Gate])

      for {flag_name, enabled} <- flags do
        gate = gate_mod.new(:boolean, enabled)
        SandboxCase.Sandbox.FwfStore.put(table, flag_name, gate)
      end

      table
    end
  end

  @impl true
  def checkin(nil), do: :ok

  def checkin(table) do
    Process.delete(:fwf_sandbox)

    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:checkin, table})
    end

    :ok
  end

  # --- GenServer pool ---

  @impl true
  def init(pool_size) do
    tables =
      for i <- 1..pool_size do
        :ets.new(:"fwf_sandbox_#{i}", [:set, :public, read_concurrency: true])
      end

    {:ok, %{available: tables, waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:checkout, _from, %{available: [table | rest]} = state) do
    :ets.delete_all_objects(table)
    {:reply, table, %{state | available: rest}}
  end

  def handle_call(:checkout, from, %{available: []} = state) do
    {:noreply, %{state | waiting: :queue.in(from, state.waiting)}}
  end

  def handle_call({:checkin, table}, _from, %{available: available, waiting: waiting} = state) do
    case :queue.out(waiting) do
      {{:value, next}, new_waiting} ->
        :ets.delete_all_objects(table)
        GenServer.reply(next, table)
        {:reply, :ok, %{state | waiting: new_waiting}}

      {:empty, _} ->
        {:reply, :ok, %{state | available: [table | available]}}
    end
  end
end
