defmodule SandboxCase.TestApp.Repo do
  use Ecto.Repo, otp_app: :sandbox_case, adapter: Ecto.Adapters.SQLite3
end
