defmodule SandboxCase.IntegrationTest do
  use ExUnit.Case, async: true
  use SandboxCase.Sandbox.Case
  use Mimic

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint SandboxCase.TestApp.Endpoint

  alias SandboxCase.TestApp.{Repo, Item}

  describe "Ecto sandbox" do
    test "LiveView sees test data", %{sandbox: sandbox} do
      Repo.insert!(%Item{name: "test-item"})

      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/items")

      assert render(view) =~ "test-item"
    end

    test "data doesn't leak between tests", %{sandbox: sandbox} do
      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/items")

      refute render(view) =~ "test-item"
    end
  end

  describe "Mimic stubs" do
    test "stub propagates to LiveView", %{sandbox: sandbox} do
      Mimic.stub(SandboxCase.TestApp.ExternalService, :greeting, fn ->
        "Hello from test"
      end)

      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/greeting")

      assert render(view) =~ "Hello from test"
    end
  end

  describe "Mox stubs" do
    setup do
      Mox.set_mox_from_context(%{async: true})
      :ok
    end

    test "stub propagates to LiveView", %{sandbox: sandbox} do
      Mox.stub(SandboxCase.TestApp.MockWeather, :temperature, fn -> "72°F" end)

      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/weather")

      assert render(view) =~ "72°F"
    end
  end

  describe "Cachex sandbox" do
    test "isolated cache with DB fallback", %{sandbox: sandbox} do
      Repo.insert!(%Item{name: "cached-item"})

      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/cached")

      assert render(view) =~ "cached-item"
    end

    test "cache doesn't leak between tests", %{sandbox: sandbox} do
      Repo.insert!(%Item{name: "other-item"})

      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/cached")

      assert render(view) =~ "other-item"
      refute render(view) =~ ">cached-item<"
    end
  end

  describe "FunWithFlags sandbox" do
    test "flag enabled in test is visible to LiveView", %{sandbox: sandbox} do
      FunWithFlags.enable(:test_feature)

      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/flagged")

      assert render(view) =~ "feature-on"
    end

    test "flags don't leak between tests", %{sandbox: sandbox} do
      conn = build_conn_with_sandbox(sandbox)
      {:ok, view, _html} = live(conn, "/flagged")

      assert render(view) =~ "feature-off"
    end
  end

  describe "Logger sandbox" do
    test "captures logs from test process only", %{sandbox: sandbox} do
      require Logger
      Logger.info("hello from this test")

      logs = SandboxCase.Sandbox.Logger.get_logs(sandbox)
      assert Enum.any?(logs, &(&1.message =~ "hello from this test"))
    end

    test "captures logs from controller requests", %{sandbox: sandbox} do
      conn = build_conn() |> get("/page")
      assert conn.status == 200

      logs = SandboxCase.Sandbox.Logger.get_logs(sandbox)
      assert Enum.any?(logs, &(&1.message =~ "page controller hit"))
    end

    test "logs don't leak between tests", %{sandbox: sandbox} do
      require Logger
      Logger.info("different test")

      logs = SandboxCase.Sandbox.Logger.get_logs(sandbox)
      refute Enum.any?(logs, &(&1.message =~ "hello from this test"))
      assert Enum.any?(logs, &(&1.message =~ "different test"))
    end

    test "fail_on: :error raises on error logs" do
      require Logger

      sandbox = SandboxCase.Sandbox.checkout(sandbox: [logger: [fail_on: :error]])

      Logger.error("something broke")

      assert_raise RuntimeError, ~r/1 unconsumed log.*at error or above/, fn ->
        SandboxCase.Sandbox.checkin(sandbox)
      end
    end

    test "fail_on: :warning raises on warning logs" do
      require Logger

      sandbox = SandboxCase.Sandbox.checkout(sandbox: [logger: [fail_on: :warning]])

      Logger.warning("hmm")

      assert_raise RuntimeError, ~r/1 unconsumed log.*at warning or above/, fn ->
        SandboxCase.Sandbox.checkin(sandbox)
      end
    end

    test "fail_on: false never raises" do
      require Logger

      sandbox = SandboxCase.Sandbox.checkout(sandbox: [logger: [fail_on: false]])

      Logger.error("ignored")

      assert :ok = SandboxCase.Sandbox.checkin(sandbox)
    end

    test "captures logs from spawned processes", %{sandbox: sandbox} do
      require Logger

      task = Task.async(fn -> Logger.warning("from child") end)
      Task.await(task)

      logs = SandboxCase.Sandbox.Logger.get_logs(sandbox)
      assert Enum.any?(logs, &(&1.message =~ "from child"))
    end

    test "pop_log consumes a single entry", %{sandbox: sandbox} do
      require Logger
      Logger.error("first error")
      Logger.error("second error")

      assert SandboxCase.Sandbox.Logger.pop_log(sandbox, :error) =~ "first error"
      assert SandboxCase.Sandbox.Logger.pop_log(sandbox, :error) =~ "second error"
      refute SandboxCase.Sandbox.Logger.pop_log(sandbox, :error)
    end

    test "pop_log filters by level", %{sandbox: sandbox} do
      require Logger
      Logger.info("info msg")
      Logger.error("error msg")

      assert SandboxCase.Sandbox.Logger.pop_log(sandbox, :error) =~ "error msg"
      # info is still there
      assert SandboxCase.Sandbox.Logger.pop_log(sandbox, :info) =~ "info msg"
    end

    test "logs/2 pops all matching entries", %{sandbox: sandbox} do
      require Logger
      Logger.warning("warn one")
      Logger.warning("warn two")
      Logger.info("info msg")

      result = SandboxCase.Sandbox.Logger.logs(sandbox, :warning)
      assert result =~ "warn one"
      assert result =~ "warn two"

      # warnings consumed, info still there
      assert SandboxCase.Sandbox.Logger.pop_log(sandbox, :info) =~ "info msg"
      refute SandboxCase.Sandbox.Logger.pop_log(sandbox, :warning)
    end

    test "consumed errors don't fail checkin" do
      require Logger

      sandbox = SandboxCase.Sandbox.checkout(sandbox: [logger: [fail_on: :error]])

      Logger.error("expected error")
      # Consume it
      SandboxCase.Sandbox.Logger.pop_log(sandbox, :error)

      # Checkin should pass — the error was consumed
      assert :ok = SandboxCase.Sandbox.checkin(sandbox)
    end

    test "unconsumed errors fail checkin" do
      require Logger

      sandbox = SandboxCase.Sandbox.checkout(sandbox: [logger: [fail_on: :error]])

      Logger.error("expected error")
      Logger.error("unexpected error")

      # Only consume one
      SandboxCase.Sandbox.Logger.pop_log(sandbox, :error)

      # Checkin fails — one unconsumed error remains
      assert_raise RuntimeError, ~r/1 unconsumed log/, fn ->
        SandboxCase.Sandbox.checkin(sandbox)
      end
    end
  end

  describe "Orphan cleanup" do
    test "kills orphaned processes on checkin" do
      test_pid = self()

      {:ok, orphan} =
        Task.start(fn ->
          Process.put(:"$callers", [test_pid])
          Process.sleep(:infinity)
        end)

      Process.sleep(10)
      assert Process.alive?(orphan)

      SandboxCase.Sandbox.kill_orphans(test_pid)

      Process.sleep(10)
      refute Process.alive?(orphan)
    end

    test "kill_orphans is a no-op when no orphans" do
      assert :ok = SandboxCase.Sandbox.kill_orphans(self())
    end
  end

  defp build_conn_with_sandbox(sandbox) do
    case SandboxCase.Sandbox.ecto_metadata(sandbox) do
      nil ->
        build_conn()

      metadata ->
        ua = Phoenix.Ecto.SQL.Sandbox.encode_metadata(metadata)

        build_conn()
        |> Plug.Conn.put_req_header("user-agent", ua)
    end
  end
end
