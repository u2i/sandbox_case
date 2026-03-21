defmodule SandboxCase.Sandbox.Cachex do
  @moduledoc """
  Sandbox adapter for Cachex. Works with vanilla Cachex — no fork required.

  On setup, patches `Cachex.Services.Overseer.retrieve/1` to check the
  process dictionary for sandbox overrides, then starts a pool of isolated
  Cachex instances. Each test checks out a clean set and checks it back in.

      config :sandbox_case,
        sandbox: [cachex: [:my_cache, :other_cache]]
  """
  @behaviour SandboxCase.Sandbox.Adapter
  use GenServer

  @impl true
  def available? do
    Code.ensure_loaded?(Cachex)
  end

  @impl true
  def setup(config) do
    names = extract_names(config)
    pool_size = config[:pool_size] || System.schedulers_online()

    # Patch Overseer to check process dictionary
    SandboxCase.Sandbox.CachexPatcher.patch!()

    # Start the pool
    {:ok, _} = GenServer.start_link(__MODULE__, {names, pool_size}, name: __MODULE__)
    :ok
  end

  @impl true
  def propagate_keys(config) do
    names = extract_names(config)
    Enum.map(names, &{:cachex_sandbox, &1})
  end

  @impl true
  def checkout(_config) do
    if Process.whereis(__MODULE__) do
      caches = GenServer.call(__MODULE__, :checkout, 5_000)

      for {name, instance} <- caches do
        Process.put({:cachex_sandbox, name}, instance)
      end

      caches
    end
  end

  @impl true
  def checkin(nil), do: :ok

  def checkin(caches) do
    for {name, _instance} <- caches do
      Process.delete({:cachex_sandbox, name})
    end

    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:checkin, caches})
    end

    :ok
  end

  # --- GenServer pool ---

  @impl true
  def init({cache_names, pool_size}) do
    instances =
      for i <- 1..pool_size do
        for name <- cache_names, into: %{} do
          instance_name = :"#{name}_sandbox_#{i}"
          {:ok, _} = Cachex.start_link(instance_name)
          {name, instance_name}
        end
      end

    {:ok, %{available: instances, waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:checkout, _from, %{available: [instance | rest]} = state) do
    clear_all(instance)
    {:reply, instance, %{state | available: rest}}
  end

  def handle_call(:checkout, from, %{available: []} = state) do
    {:noreply, %{state | waiting: :queue.in(from, state.waiting)}}
  end

  def handle_call({:checkin, caches}, _from, state) do
    case :queue.out(state.waiting) do
      {{:value, waiter}, waiting} ->
        clear_all(caches)
        GenServer.reply(waiter, caches)
        {:reply, :ok, %{state | waiting: waiting}}

      {:empty, _} ->
        {:reply, :ok, %{state | available: [caches | state.available]}}
    end
  end

  defp clear_all(instance_map) do
    for {_name, instance} <- instance_map, do: Cachex.clear(instance)
  end

  defp extract_names(config) when is_list(config) do
    case Keyword.get(config, :names) do
      nil -> Enum.filter(config, &is_atom/1)
      names -> names
    end
  end
end
