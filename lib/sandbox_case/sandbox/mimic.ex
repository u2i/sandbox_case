defmodule SandboxCase.Sandbox.Mimic do
  @moduledoc false
  @behaviour SandboxCase.Sandbox.Adapter

  @cache_key {__MODULE__, :copied_modules}

  @impl true
  def available? do
    Code.ensure_loaded?(Mimic)
  end

  @impl true
  def setup(config) do
    mimic = Module.concat([Mimic])
    modules = modules(config)

    for mod <- modules do
      mimic.copy(mod)
    end

    :persistent_term.put(@cache_key, modules)

    :ok
  end

  # Resolve the list of modules to Mimic.copy from the adapter config.
  # Accepts:
  #   * `[modules: [Mod, ...]]`        — explicit, keyword form
  #   * `[Mod, ...]`                   — bare list of modules
  #   * `true` → normalized to `[otp_app: app]` by SandboxCase.Sandbox —
  #     no modules to copy (there's no generic way to discover intended
  #     stub targets from an otp_app), so this is a no-op rather than a
  #     crash. Use the explicit form to list modules.
  #
  # Crucially this never falls back to iterating the raw keyword config,
  # which previously turned `mimic: true` into
  # `Mimic.copy({:otp_app, app})` and raised.
  defp modules(config) when is_list(config) do
    cond do
      is_list(config[:modules]) -> config[:modules]
      Keyword.keyword?(config) -> []
      true -> config
    end
  end

  defp modules(_config), do: []

  @impl true
  def checkout(_config), do: nil

  @impl true
  def checkin(_token), do: :ok

  @doc """
  Returns the list of modules registered at setup time. Used by the
  Propagator to avoid an expensive `:sys.get_state(Mimic.Server)` call
  on every HTTP request — under concurrent load Mimic.Server's mailbox
  can be contended enough that serializing its full state times out or
  stalls, causing silent Mimic-stub propagation failures.
  """
  def copied_modules do
    :persistent_term.get(@cache_key, [])
  end
end
