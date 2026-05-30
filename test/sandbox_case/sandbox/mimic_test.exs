defmodule SandboxCase.Sandbox.MimicTest do
  use ExUnit.Case, async: false

  alias SandboxCase.Sandbox.Mimic, as: MimicAdapter
  alias SandboxCase.TestApp.ExternalService

  # `setup/1` calls Mimic.copy/1 on each resolved module. Mimic.copy is
  # idempotent and ExternalService is already copied via config/test.exs,
  # so re-copying here is harmless.

  describe "setup/1 module resolution" do
    test "explicit [modules: [...]] form copies the listed modules" do
      assert :ok = MimicAdapter.setup(modules: [ExternalService])
      assert MimicAdapter.copied_modules() == [ExternalService]
    end

    test "bare list form copies the listed modules" do
      assert :ok = MimicAdapter.setup([ExternalService])
      assert MimicAdapter.copied_modules() == [ExternalService]
    end

    test "normalized `true` form ([otp_app: app]) is a no-op, not a crash" do
      # SandboxCase.Sandbox.normalize_config turns `mimic: true` into
      # [otp_app: app]. This must not try to Mimic.copy({:otp_app, app}).
      assert :ok = MimicAdapter.setup(otp_app: :sandbox_case)
      assert MimicAdapter.copied_modules() == []
    end

    test "keyword config without :modules copies nothing" do
      assert :ok = MimicAdapter.setup(otp_app: :sandbox_case, something: :else)
      assert MimicAdapter.copied_modules() == []
    end
  end
end
