defmodule SandboxCase.Sandbox.Ecto do
  @moduledoc false
  @behaviour SandboxCase.Sandbox.Adapter

  # Process-dictionary key, set on the TEST process by checkout/1, holding
  # the real Ecto owner Agent pid(s) started via start_owner!/2. Read back
  # by propagate_keys/1 so Propagator.set_callers/1 can extend $callers
  # with the real Ecto owners, once `owner` itself has been corrected
  # (below) to mean the test process rather than an Ecto Agent.
  @callers_key {__MODULE__, :owners}

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
    test_pid = self()

    owners =
      for repo <- repos do
        {repo, sql_sandbox.start_owner!(repo, shared: not async?)}
      end

    # Stash the Ecto owner Agent pid(s) in the TEST process's own
    # dictionary (not the metadata below) so Propagator.set_callers/1 can
    # find them via propagate_keys/1 once it has already resolved the
    # test process as `owner` -- see propagate_keys/1 for why this needs
    # to be a separate channel from `metadata`'s `owner:` field.
    Process.put(@callers_key, Enum.map(owners, &elem(&1, 1)))

    # Only generate metadata for async (manual-mode) checkouts. In shared
    # mode, all processes already have DB access without explicit
    # allowances, and (unlike the old checkout/2-based code this replaces)
    # there is no self-collision risk here: start_owner! already calls
    # allow(repo, owner_pid, test_pid) itself in the non-shared branch, so
    # the owner and the allowed caller are always distinct processes.
    #
    # Deliberately `owner: test_pid`, NOT the Ecto owner Agent(s) above:
    # this metadata's `owner` is what Propagator.propagate/2 later uses
    # for Mimic/Mox allowances and process-dictionary propagation, and
    # those need the process that actually called Mimic.stub/Mox.expect
    # (the test process) -- under 0.4.3's checkout/2, that coincided with
    # the Ecto connection owner (both were the test process itself); with
    # start_owner!/2 they're genuinely different processes, and
    # conflating them here silently broke Mimic/Mox propagation (the stub
    # ends up "allowed" under a pid -- the Ecto Agent -- that never
    # actually called stub/expect, so Server.apply's lookup never finds
    # it and falls through to the real, unstubbed implementation).
    metadata =
      if async? and Code.ensure_loaded?(phoenix_sandbox) and owners != [] do
        phoenix_sandbox.metadata_for(Enum.map(owners, &elem(&1, 0)), test_pid)
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

  @impl true
  def propagate_keys(_config), do: [@callers_key]

  defp repos(config) do
    case config[:repos] do
      repos when is_list(repos) -> repos
      nil -> discover_repos(config[:otp_app])
    end
  end

  defp discover_repos(nil), do: []
  defp discover_repos(otp_app), do: Application.get_env(otp_app, :ecto_repos, [])
end
