defmodule SandboxCase.Sandbox.Ecto do
  @moduledoc false
  @behaviour SandboxCase.Sandbox.Adapter

  @impl true
  def available? do
    Code.ensure_loaded?(Ecto.Adapters.SQL.Sandbox)
  end

  @impl true
  def setup(config) do
    sql_sandbox = Module.concat([Ecto, Adapters, SQL, Sandbox])

    for repo <- repos(config) do
      sql_sandbox.mode(repo, :manual)
    end

    :ok
  end

  @impl true
  def checkout(config) do
    # start_owner!/2, not checkout/2: per Ecto's own docs, checkout/2 ties
    # the DBConnection owner to the calling process, which is exactly wrong
    # for a LiveView (linked to its own supervisor, not the test process)
    # or a remote/browser-driven request process that must keep using the
    # connection past anything the caller does. start_owner!/2 spawns a
    # separate, independently-supervised Agent as owner instead, and is
    # phoenix_ecto's own documented pattern for wiring Phoenix.Ecto.SQL.Sandbox
    # (channels/LiveView/acceptance tests) across process boundaries.
    #
    # This does not, on its own, prevent the race stop_liveviews (below)
    # exists for: start_owner! only changes WHICH process owns the
    # connection, not WHEN checkin/1 tears that owner down. Both are
    # needed together.
    async? = config[:async?] || false
    sql_sandbox = Module.concat([Ecto, Adapters, SQL, Sandbox])
    phoenix_sandbox = Module.concat([Phoenix, Ecto, SQL, Sandbox])

    repos = repos(config)

    owners =
      for repo <- repos do
        {repo, sql_sandbox.start_owner!(repo, shared: not async?)}
      end

    # Only generate metadata for async (manual-mode) checkouts. In shared
    # mode, all processes already have DB access without explicit
    # allowances, and (unlike the old checkout/2-based code this replaces)
    # there is no self-collision risk here: start_owner! already calls
    # allow(repo, owner_pid, test_pid) itself in the non-shared branch, so
    # the owner and the allowed caller are always distinct processes.
    metadata =
      if async? and Code.ensure_loaded?(phoenix_sandbox) and owners != [] do
        {_first_repo, first_owner} = List.first(owners)
        phoenix_sandbox.metadata_for(Enum.map(owners, &elem(&1, 0)), first_owner)
      end

    %{owners: owners, metadata: metadata}
  end

  @impl true
  def checkin(%{owners: owners}) do
    sql_sandbox = Module.concat([Ecto, Adapters, SQL, Sandbox])

    # checkin/1 can run twice for the same sandbox (e.g. a test calls it
    # explicitly, then SandboxCase.Sandbox.Case's own on_exit calls it
    # again). checkout/2 + Ecto's checkin/1 tolerated that; stop_owner/1
    # is GenServer.stop on a specific pid and raises if that agent is
    # already gone. Swallow "already stopped" so checkin/1 stays
    # idempotent, matching the old behavior.
    for {_repo, owner_pid} <- owners do
      if Process.alive?(owner_pid) do
        try do
          sql_sandbox.stop_owner(owner_pid)
        catch
          :exit, _ -> :ok
        end
      end
    end

    :ok
  end

  def checkin(_), do: :ok

  @impl true
  def plugs do
    plug = Module.concat([Phoenix, Ecto, SQL, Sandbox])
    sandbox_plug = SandboxCase.Sandbox.Plug

    Enum.filter([plug, sandbox_plug], &Code.ensure_loaded?/1)
  end

  @impl true
  def hooks do
    hook = SandboxCase.Sandbox.Hook

    if Code.ensure_loaded?(hook), do: [hook], else: []
  end

  defp repos(config) do
    case config[:repos] do
      repos when is_list(repos) -> repos
      nil -> discover_repos(config[:otp_app])
    end
  end

  defp discover_repos(nil), do: []
  defp discover_repos(otp_app), do: Application.get_env(otp_app, :ecto_repos, [])
end
