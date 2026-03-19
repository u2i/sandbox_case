# PhoenixTestOnly

Compile-time conditional `plug` and `on_mount` for test-only modules.

Phoenix's `plug` and `on_mount` macros accumulate module attributes at the top level. When wrapped in `if Application.compile_env(...)`, the call ends up inside a `case` node in the AST and Phoenix silently ignores it.

These macros move the check to **macro expansion time**: the emitted code is either a bare `plug`/`on_mount` call or nothing at all.

## Installation

```elixir
{:phoenix_test_only, "~> 0.1"}
```

## Usage

```elixir
# endpoint.ex
import PhoenixTestOnly
plug_if_loaded MyApp.Sandbox.Plug

# your_app_web.ex
def live_view do
  quote do
    use Phoenix.LiveView
    import PhoenixTestOnly
    on_mount_if_loaded MyApp.Sandbox.Hook
  end
end
```

When the target module isn't loaded (e.g. a test-only dep not present in prod), the macro emits nothing.

## License

MIT
