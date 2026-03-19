defmodule PhoenixTestOnlyTest do
  use ExUnit.Case, async: true

  describe "test_env?/0" do
    test "returns true when Mix is available and env is :test" do
      assert PhoenixTestOnly.test_env?()
    end
  end

  describe "Sandbox" do
    test "setup with no config is a no-op" do
      assert :ok = PhoenixTestOnly.Sandbox.setup(sandbox: [])
    end

    test "checkout/checkin round-trip with no adapters" do
      tokens = PhoenixTestOnly.Sandbox.checkout(sandbox: [])
      assert tokens == []
      assert :ok = PhoenixTestOnly.Sandbox.checkin(tokens)
    end

    test "skips unavailable adapters" do
      tokens = PhoenixTestOnly.Sandbox.checkout(sandbox: [cachex: [:nonexistent]])
      assert tokens == []
    end

    test "ecto_metadata returns nil when no ecto token" do
      assert PhoenixTestOnly.Sandbox.ecto_metadata([]) == nil
    end

    test "collect_plugs returns empty list when no adapters configured" do
      prev = Application.get_env(:phoenix_test_only, :sandbox)
      Application.put_env(:phoenix_test_only, :sandbox, [])
      assert PhoenixTestOnly.Sandbox.collect_plugs() == []
      if prev, do: Application.put_env(:phoenix_test_only, :sandbox, prev), else: Application.delete_env(:phoenix_test_only, :sandbox)
    end

    test "collect_hooks returns empty list when no adapters configured" do
      prev = Application.get_env(:phoenix_test_only, :sandbox)
      Application.put_env(:phoenix_test_only, :sandbox, [])
      assert PhoenixTestOnly.Sandbox.collect_hooks() == []
      if prev, do: Application.put_env(:phoenix_test_only, :sandbox, prev), else: Application.delete_env(:phoenix_test_only, :sandbox)
    end
  end
end
