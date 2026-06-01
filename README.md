# SandboxCase

Batteries-included test isolation for Elixir and Phoenix.

## The problem

Getting test isolation right in Elixir is surprisingly fiddly. Ecto has its SQL Sandbox, but everything else — caches, feature flags, mocks, GenServers — is shared global state that leaks between tests. The more your app uses these, the worse it gets:

- **Caches** (Cachex, ConCache) retain data between tests. A test that writes to a cache poisons every test that runs after it.
- **Feature flags** (FunWithFlags) are global. Enabling a flag in one test enables it everywhere.
- **Mocks** (Mimic, Mox) need explicit `allow` or `$callers` wiring to reach spawned processes — LiveViews, GenServers, async tasks.
- **Async tests** make all of this harder. Every process in the call chain needs to participate in the sandbox, or you get `DBConnection.OwnershipError` and mysterious "cannot find ownership process" crashes.

The common workaround is giving up on `async: true` and running everything synchronously. This is safe but slow, and doesn't actually fix the cache/flag leakage — it just makes it less likely to bite you.

A better default: **no shared state survives between tests**. Each test gets its own database transaction, its own cache instance, its own feature flag store, its own mock context. SandboxCase sets this up with one config and one line in test_helper.

Crucially, each adapter isolates state in a way that's native to the library — Ecto gets a wrapped transaction, Cachex gets a real but isolated cache instance, FunWithFlags gets its own ETS table. Your tests still exercise the actual library code paths, so you catch real bugs in how your app uses the dependency. You can always fully mock a dependency (which itself benefits from the batteries-included approach) when that's what your test calls for — but when you don't, the default should be clean isolation, not leaked state.

## How it works

One config, one setup call, zero boilerplate. Built-in adapters for Ecto, Cachex, FunWithFlags, Mimic, Mox, and Redis — each activated only if the dep is loaded.

All macros expand at compile time. Outside `MIX_ENV=test`, `sandbox_plugs` and `sandbox_on_mount` emit nothing, and `socket_with_sandbox` emits a plain `socket` call. No runtime checks, no dead branches, no production dependencies on test libraries.

### How Cachex and FunWithFlags isolation works (and version compatibility)

Ecto, Mimic, and Mox expose first-class hooks for redirecting state per
process. Cachex and FunWithFlags do **not** — neither library has a
supported way to route a cache/flag lookup to a different backing store
based on the calling process. To isolate them per test *without forking*,
sandbox_case **patches them at runtime** (in `MIX_ENV=test` only): it
reads the dependency module's compiled `:abstract_code`, rewrites it, and
replaces the module via `Module.create`, so that when a sandbox marker is
present in the process dictionary (or reachable via `$callers`), reads and
writes route to an isolated ETS table instead of the shared store.

> ⚠️ **Version coupling.** Because this rewrites the dependency's own
> internals, it is tied to the implementation shape of specific versions.
> The patchers are written and tested against:
>
> | Library | Tested version | Patched surface |
> |---------|----------------|-----------------|
> | Cachex | `4.1.x` | `Cachex.Services.Overseer` name resolution |
> | FunWithFlags | `1.13.x` | `FunWithFlags.Store` / `SimpleStore` |
>
> Each patcher **probes the target's shape before patching** and, if it
> doesn't match (a newer version refactored the internals), **skips the
> patch and logs a warning** rather than crashing. The failure mode is
> therefore *lost isolation with a warning*, not a hard error — so if you
> upgrade Cachex/FunWithFlags past the tested range, watch the test logs
> for `SandboxCase: ... doesn't match expected shape`. (Note: Cachex on
> its `main` branch has already renamed the patched `Overseer.retrieve/1`
> to `lookup/1`, so the next Cachex release is expected to trip this.)
>
> The long-term fix is a supported, non-bytecode hook upstream — see
> [whitfin/cachex#436](https://github.com/whitfin/cachex/pull/436), which
> proposes a per-process name resolver. FunWithFlags can already be
> isolated without patching via a custom `FunWithFlags.Store.Persistent`
> adapter plus `config :fun_with_flags, :cache, enabled: false`; a future
> sandbox_case release is expected to move to that approach.

## Installation

```elixir
{:sandbox_case, "~> 0.1"}
```

## Configuration

```elixir
# config/test.exs
config :sandbox_case,
  otp_app: :my_app,
  mox_mocks: [MyApp.MockWeather],
  sandbox: [
    ecto: true,
    cachex: [:my_cache],
    fun_with_flags: true,
    mimic: [MyApp.ExternalService, MyApp.Payments],
    mox: [{MyApp.MockWeather, MyApp.WeatherBehaviour}],
    redis: [url: "redis://localhost:6379"]
  ]
```

## Setup

```elixir
# test/test_helper.exs
SandboxCase.Sandbox.setup()
ExUnit.start()
```

## Endpoint and LiveView

```elixir
# lib/your_app_web/endpoint.ex
import SandboxCase
sandbox_plugs()

socket_with_sandbox "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [session: @session_options]]
```

```elixir
# lib/your_app_web.ex
def live_view do
  quote do
    use Phoenix.LiveView
    import SandboxCase
    sandbox_on_mount()
  end
end
```

Outside test env, both macros emit nothing.

## Test modules

```elixir
use SandboxCase.Sandbox.Case
```

Checks out all sandboxes in `setup`, checks them back in via `on_exit`. Ecto metadata for browser sessions:

```elixir
SandboxCase.Sandbox.ecto_metadata(context.sandbox_tokens)
```

## GenServers and sandbox access

Ecto sandbox, Mimic stubs, and Mox mocks are resolved via `$callers` — a process dictionary key that Elixir's `Task` module sets automatically. `GenServer.start_link` does **not** set it, so a GenServer started from a LiveView or test won't see sandboxed state by default.

The fix: pass `$callers` explicitly when starting the GenServer.

```elixir
defmodule MyApp.PriceServer do
  use GenServer

  def start_supervised(opts \\ []) do
    callers = [self() | Process.get(:"$callers", [])]
    GenServer.start_link(__MODULE__, Keyword.put(opts, :callers, callers))
  end

  @impl true
  def init(opts) do
    if callers = opts[:callers], do: Process.put(:"$callers", callers)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:fetch_price, _from, state) do
    # This works in tests — Mimic finds the test process via $callers,
    # and Ecto finds the sandbox connection the same way.
    price = MyApp.PriceService.fetch_price()
    {:reply, price, state}
  end
end
```

This pattern works for any process you spawn that needs access to the test sandbox: GenServers, Agents, custom processes via `spawn_link`, etc. `Task.start_link` and `Task.async` handle this automatically.

## Custom adapters

Implement `SandboxCase.Sandbox.Adapter` to add isolation for any shared state.

```elixir
defmodule MyApp.RedisSandbox do
  @behaviour SandboxCase.Sandbox.Adapter

  # Is the dep available? Return false to skip this adapter entirely.
  @impl true
  def available?, do: Code.ensure_loaded?(Redix)

  # One-time setup — called from test_helper.exs via SandboxCase.Sandbox.setup().
  # Use this to start pools, create isolation resources, etc.
  @impl true
  def setup(config) do
    pool_size = config[:pool_size] || 4
    # ... start a pool of Redis connections
    :ok
  end

  # Per-test checkout — called in each test's setup.
  # Return an opaque token that will be passed to checkin/1.
  @impl true
  def checkout(_config) do
    # ... claim an isolated Redis DB, flush it
    %{db: db_number}
  end

  # Per-test checkin — called in on_exit.
  @impl true
  def checkin(nil), do: :ok
  def checkin(%{db: db}) do
    # ... release the Redis DB back to the pool
    :ok
  end

  # Optional: plug modules to register in the endpoint.
  # Omit this callback if your adapter doesn't need a plug.
  @impl true
  def plugs, do: []

  # Optional: on_mount modules to register in LiveViews.
  # Omit this callback if your adapter doesn't need a hook.
  @impl true
  def hooks, do: []
end
```

Register it in config:

```elixir
config :sandbox_case,
  sandbox: [
    ecto: true,
    {MyApp.RedisSandbox, pool_size: 4}
  ]
```

The adapter lifecycle:

1. `available?/0` — checked at compile time (for plugs/hooks) and runtime (for setup/checkout). Return `false` to skip.
2. `setup/1` — called once from `SandboxCase.Sandbox.setup()` in test_helper.
3. `checkout/1` — called per test. Returns a token.
4. `checkin/1` — called in `on_exit` with the token from checkout.
5. `plugs/0` — (optional) modules emitted by `sandbox_plugs()`.
6. `hooks/0` — (optional) modules emitted by `sandbox_on_mount()`.

## License

MIT
