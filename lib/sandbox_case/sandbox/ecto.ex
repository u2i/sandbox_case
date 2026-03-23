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
    async? = config[:async?] || false
    sql_sandbox = Module.concat([Ecto, Adapters, SQL, Sandbox])

    repos = repos(config)

    for repo <- repos do
      :ok = sql_sandbox.checkout(repo)
      unless async?, do: sql_sandbox.mode(repo, {:shared, self()})
    end

    phoenix_sandbox = Module.concat([Phoenix, Ecto, SQL, Sandbox])

    metadata =
      if Code.ensure_loaded?(phoenix_sandbox) and repos != [] do
        phoenix_sandbox.metadata_for(repos, self())
      end

    %{repos: repos, metadata: metadata}
  end

  @impl true
  def checkin(%{repos: repos}) do
    sql_sandbox = Module.concat([Ecto, Adapters, SQL, Sandbox])

    for repo <- repos do
      sql_sandbox.checkin(repo)
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
