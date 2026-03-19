# PhoenixTestOnly

Test sandbox orchestration for Phoenix apps. One config, one setup call, zero boilerplate.

## Installation

```elixir
# mix.exs — include in all envs (macros need to run at compile time)
{:phoenix_test_only, "~> 0.4"}
```

## Configuration

```elixir
# config/test.exs
config :phoenix_test_only,
  otp_app: :my_app,
  mox_mocks: [MyApp.MockWeather],
  sandbox: [
    ecto: true,
    cachex: [:my_cache],
    fun_with_flags: true,
    mimic: [MyApp.ExternalService, MyApp.Payments],
    mox: [{MyApp.MockWeather, MyApp.WeatherBehaviour}]
  ]
```

Each adapter is only activated if its dep is loaded. Custom adapters can implement `PhoenixTestOnly.Sandbox.Adapter`.

## Setup

```elixir
# test/test_helper.exs
PhoenixTestOnly.Sandbox.setup()
ExUnit.start()
```

## Endpoint and LiveView

```elixir
# lib/your_app_web/endpoint.ex
import PhoenixTestOnly
sandbox_plugs()

socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:user_agent, session: @session_options]]
```

```elixir
# lib/your_app_web.ex
def live_view do
  quote do
    use Phoenix.LiveView
    import PhoenixTestOnly
    sandbox_on_mount()
  end
end
```

The macros read your sandbox config at compile time and emit the right `plug`/`on_mount` calls. Outside test env, they emit nothing.

## Test modules

```elixir
use PhoenixTestOnly.Sandbox.Case
```

Checks out all sandboxes in `setup`, checks them back in via `on_exit`. Ecto metadata for browser sessions:

```elixir
PhoenixTestOnly.Sandbox.ecto_metadata(context.sandbox_tokens)
```

## What's included

**Adapters** for Ecto, Cachex, FunWithFlags, Mimic, and Mox — each handles setup and per-test checkout/checkin.

**Sandbox Plug** (`PhoenixTestOnly.Sandbox.Plug`) — propagates Ecto sandbox, Mimic/Mox stubs, Cachex sandbox, and FunWithFlags sandbox to HTTP request processes.

**Sandbox Hook** (`PhoenixTestOnly.Sandbox.Hook`) — same propagation for LiveView WebSocket processes. Uses `$callers` for Ecto instead of `allow/3` to avoid deadlocks with Cachex Courier workers.

**Compile-time macros** — `sandbox_plugs()`, `sandbox_on_mount()`, `plug_if_test`, `on_mount_if_test`.

## License

MIT
