defmodule PhoenixTestOnly.Sandbox.Propagator do
  @moduledoc false
  # Shared logic for propagating test sandbox state (Ecto, Mimic, Mox,
  # Cachex, FunWithFlags) from a test owner process to a child process.

  @doc "Propagate all sandbox state from owner to the current process."
  def propagate(owner, child \\ self()) do
    set_callers(owner)
    allow_mimic(owner, child)
    allow_mox(owner, child)
    propagate_process_dict(owner)
  end

  # Ecto — set $callers so this process and its sub-processes can access
  # the test sandbox via the ownership chain. Avoids the deadlock that
  # occurs with allow/3 (see Wallabidi.Sandbox.Hook for details).
  defp set_callers(owner) do
    callers = Process.get(:"$callers") || []
    unless owner in callers, do: Process.put(:"$callers", [owner | callers])
  end

  defp allow_mimic(owner, child) do
    mimic = Module.concat([Mimic])

    if Code.ensure_loaded?(mimic) do
      server = Module.concat([Mimic, Server])

      for mod <- mimic_modules(server) do
        mimic.allow(mod, owner, child)
      end
    end
  catch
    _, _ -> :ok
  end

  defp mimic_modules(server) do
    :sys.get_state(server).modules_opts |> Map.keys()
  catch
    _, _ -> []
  end

  defp allow_mox(owner, child) do
    mox = Module.concat([Mox])

    if Code.ensure_loaded?(mox) do
      mocks =
        Application.get_env(:phoenix_test_only, :mox_mocks, []) ++
          Application.get_env(:wallabidi, :mox_mocks, [])

      for mod <- Enum.uniq(mocks) do
        mox.allow(mod, owner, child)
      end
    end
  catch
    _, _ -> :ok
  end

  # Copy sandbox-related process dictionary entries from owner.
  defp propagate_process_dict(owner) do
    case :erlang.process_info(owner, :dictionary) do
      {:dictionary, dict} ->
        for {key, value} <- dict do
          case key do
            {:cachex_sandbox, _} -> Process.put(key, value)
            :fwf_sandbox -> Process.put(key, value)
            _ -> :ok
          end
        end

      _ ->
        :ok
    end
  catch
    _, _ -> :ok
  end
end
