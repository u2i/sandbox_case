defmodule SandboxCase.AsyncFalseTest do
  # Regression tests for the async: false (shared-mode) ownership manager crash.
  #
  # The bug: when Phoenix.Ecto.SQL.Sandbox plug ran in shared mode it called
  # allow(repo, owner, self()). Since ConnTest runs the plug in the test process,
  # self() == owner, and allow(repo, owner, owner) overwrote the DBConnection
  # ownership manager's {:owner, ref, proxy} entry with {:allowed, ref, proxy}.
  # Subsequent DB checkouts crashed the manager with a MatchError.
  use ExUnit.Case, async: false
  use SandboxCase.Sandbox.Case

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint SandboxCase.TestApp.Endpoint

  alias SandboxCase.TestApp.{Repo, Item}

  # When async: false the Sandbox.Case template passes async?: false to checkout,
  # which sets shared mode and skips metadata generation.  Using plain build_conn()
  # (no user-agent header) is the natural usage pattern — verifying it doesn't
  # crash the ownership manager is the core regression.

  describe "async: false with plain build_conn" do
    test "LiveView sees test data without sandbox metadata header", %{sandbox: _sandbox} do
      Repo.insert!(%Item{name: "shared-item"})

      {:ok, view, _html} = live(build_conn(), "/items")

      assert render(view) =~ "shared-item"
    end

    test "second sequential test still works — ownership manager not corrupted", %{
      sandbox: _sandbox
    } do
      Repo.insert!(%Item{name: "second-item"})

      {:ok, view, _html} = live(build_conn(), "/items")

      assert render(view) =~ "second-item"
    end

    test "third sequential test — manager stays healthy across multiple requests", %{
      sandbox: _sandbox
    } do
      Repo.insert!(%Item{name: "third-item"})

      # Two separate requests in the same test to exercise the manager more
      {:ok, view1, _} = live(build_conn(), "/items")
      assert render(view1) =~ "third-item"

      Repo.insert!(%Item{name: "third-item-b"})

      {:ok, view2, _} = live(build_conn(), "/items")
      assert render(view2) =~ "third-item-b"
    end
  end
end
