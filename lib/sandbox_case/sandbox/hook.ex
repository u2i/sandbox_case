if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule SandboxCase.Sandbox.Hook do
    @moduledoc """
    LiveView on_mount hook that propagates test sandbox state from the
    test owner process to WebSocket-connected LiveView processes.

    Reads the owner PID from the user-agent connect_info (encoded by
    `Phoenix.Ecto.SQL.Sandbox`) and propagates Ecto sandbox access,
    Mimic/Mox stubs, Cachex sandbox, and FunWithFlags sandbox.

    Uses `$callers` for Ecto instead of `allow/3` to avoid deadlocks
    with Cachex Courier workers (see Propagator for details).
    """
    import Phoenix.LiveView

    def on_mount(:default, _params, _session, socket) do
      if connected?(socket), do: maybe_propagate(socket)
      {:cont, socket}
    end

    defp maybe_propagate(socket) do
      with ua when is_binary(ua) <- get_connect_info(socket, :user_agent),
           true <- Code.ensure_loaded?(Phoenix.Ecto.SQL.Sandbox),
           %{owner: owner} <- Phoenix.Ecto.SQL.Sandbox.decode_metadata(ua) do
        SandboxCase.Sandbox.Propagator.propagate(owner)
      end
    end
  end
end
