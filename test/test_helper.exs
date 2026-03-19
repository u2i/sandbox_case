# Start the test app
{:ok, _} = SandboxCase.TestApp.Repo.start_link()
Ecto.Migrator.up(SandboxCase.TestApp.Repo, 1, SandboxCase.TestApp.Migration)
{:ok, _} = SandboxCase.TestApp.Endpoint.start_link()
{:ok, _} = Cachex.start_link(:test_cache)

# Mox.defmock must be called before SandboxCase.Sandbox.setup()
Mox.defmock(SandboxCase.TestApp.MockWeather, for: SandboxCase.TestApp.WeatherBehaviour)
Application.put_env(:sandbox_case, :weather_module, SandboxCase.TestApp.MockWeather)
Application.put_env(:sandbox_case, :mox_mocks, [SandboxCase.TestApp.MockWeather])

# One-line sandbox setup — handles Ecto mode, Cachex pool,
# FunWithFlags pool, Mimic.copy
SandboxCase.Sandbox.setup()

ExUnit.start()
