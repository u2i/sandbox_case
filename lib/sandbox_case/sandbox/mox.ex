defmodule SandboxCase.Sandbox.Mox do
  @moduledoc false
  @behaviour SandboxCase.Sandbox.Adapter

  @impl true
  def available? do
    Code.ensure_loaded?(Mox)
  end

  @impl true
  def setup(config) do
    mox = Module.concat([Mox])
    mocks = config[:mocks] || config

    for {mock_module, behaviour} <- mocks do
      mox.defmock(mock_module, for: behaviour)
    end

    :ok
  end

  @impl true
  def checkout(_config), do: nil

  @impl true
  def checkin(_token), do: :ok
end
