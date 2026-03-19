if Code.ensure_loaded?(Plug) do
  defmodule SandboxCase.Sandbox.Plug do
    @moduledoc """
    Plug that propagates test sandbox state from the test owner process
    to HTTP request processes (controllers, channels).

    Reads the owner PID from the user-agent header (encoded by
    `Phoenix.Ecto.SQL.Sandbox`) and propagates Ecto sandbox access,
    Mimic/Mox stubs, Cachex sandbox, and FunWithFlags sandbox.
    """
    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, _opts) do
      ua = conn |> Plug.Conn.get_req_header("user-agent") |> List.first("")

      if Code.ensure_loaded?(Phoenix.Ecto.SQL.Sandbox) do
        case Phoenix.Ecto.SQL.Sandbox.decode_metadata(ua) do
          %{owner: owner} ->
            SandboxCase.Sandbox.Propagator.propagate(owner)

          _ ->
            :ok
        end
      end

      conn
    end
  end
end
