defmodule SandboxCase.Sandbox.Propagator do
  @moduledoc false
  # Shared logic for propagating test sandbox state (Ecto, Mimic, Mox,
  # Cachex, FunWithFlags) from a test owner process to a child process.

  @doc "Propagate all sandbox state from owner to the current process."
  def propagate(owner, child \\ self()) do
    # propagate_keys first: set_callers needs the Ecto owner pid(s) the
    # Ecto adapter stashed in `owner`'s dictionary (via its
    # propagate_keys/1 callback) already copied into THIS process's
    # dictionary before it can read them.
    propagate_keys(owner)
    set_callers(owner)
    allow_mimic(owner, child)
    allow_mox(owner, child)
  end

  # Ecto — set $callers so this process and its sub-processes can access
  # the test sandbox via the ownership chain. Avoids the deadlock that
  # occurs with allow/3.
  #
  # `owner` here is the TEST process (SandboxCase.Sandbox.checkout/1's
  # self()), not itself a DBConnection owner under start_owner!/2 — the
  # actual Ecto owner Agent pid(s) live in this process's own dictionary
  # under SandboxCase.Sandbox.Ecto's propagate_keys/1 key, just copied
  # over by propagate_keys/1 above. Extend $callers with THOSE, plus
  # `owner` itself (harmless, and correct for any non-Ecto DBConnection-
  # style ownership scheme that does use the test pid directly).
  defp set_callers(owner) do
    ecto_owners = Process.get({SandboxCase.Sandbox.Ecto, :owners}, [])
    callers = Process.get(:"$callers") || []
    to_add = Enum.reject([owner | ecto_owners], &(&1 in callers))

    if to_add != [], do: Process.put(:"$callers", to_add ++ callers)
  end

  defp allow_mimic(owner, child) do
    mimic = Module.concat([Mimic])

    if Code.ensure_loaded?(mimic) do
      for mod <- SandboxCase.Sandbox.Mimic.copied_modules() do
        mimic.allow(mod, owner, child)
      end
    end
  catch
    _, _ -> :ok
  end

  defp allow_mox(owner, child) do
    mox = Module.concat([Mox])

    if Code.ensure_loaded?(mox) do
      mocks =
        Application.get_env(:sandbox_case, :mox_mocks, []) ++
          Application.get_env(:wallabidi, :mox_mocks, [])

      for mod <- Enum.uniq(mocks) do
        mox.allow(mod, owner, child)
      end
    end
  catch
    _, _ -> :ok
  end

  # O(k) where k = number of sandbox keys, not O(n) over entire process dictionary.
  defp propagate_keys(owner) do
    keys = SandboxCase.Sandbox.propagate_keys()

    case :erlang.process_info(owner, :dictionary) do
      {:dictionary, dict} ->
        for key <- keys do
          case List.keyfind(dict, key, 0) do
            {^key, value} -> Process.put(key, value)
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
