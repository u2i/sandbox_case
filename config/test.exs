import Config

config :sandbox_case, SandboxCase.TestApp.Repo,
  database: "test/support/test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :sandbox_case, SandboxCase.TestApp.Endpoint,
  http: [port: 4123],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  render_errors: [formats: [html: SandboxCase.ErrorHTML], layout: false],
  live_view: [signing_salt: "test_signing_salt"]

# FunWithFlags: route persistence through the sandbox adapter (which
# delegates to the Ecto backend when not sandboxed) and disable the cache
# so every lookup reaches the sandbox-aware store.
config :fun_with_flags, :persistence,
  adapter: SandboxCase.Sandbox.FwfAdapter,
  sandbox_real_adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: SandboxCase.TestApp.Repo

config :fun_with_flags, :cache, enabled: false

config :sandbox_case,
  otp_app: :sandbox_case,
  ecto_repos: [SandboxCase.TestApp.Repo],
  mox_mocks: [SandboxCase.TestApp.MockWeather],
  weather_module: SandboxCase.TestApp.MockWeather,
  sandbox: [
    ecto: true,
    cachex: [:test_cache],
    fun_with_flags: true,
    mimic: [SandboxCase.TestApp.ExternalService],
    logger: true
  ]
