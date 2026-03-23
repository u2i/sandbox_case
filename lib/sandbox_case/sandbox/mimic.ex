defmodule SandboxCase.Sandbox.Mimic do
  @moduledoc false
  @behaviour SandboxCase.Sandbox.Adapter

  @impl true
  def available? do
    Code.ensure_loaded?(Mimic)
  end

  @impl true
  def setup(config) do
    mimic = Module.concat([Mimic])
    modules = config[:modules] || config

    for mod <- modules do
      mimic.copy(mod)
    end

    :ok
  end

  @impl true
  def checkout(_config), do: nil

  @impl true
  def checkin(_token), do: :ok
end
