# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.5](https://github.com/u2i/sandbox_case/compare/v0.4.4...v0.4.5) (2026-08-25)


### Bug Fixes

* propagate the test process pid, not the Ecto owner Agent, to Mimic/Mox ([f11430b](https://github.com/u2i/sandbox_case/commit/f11430b66e0f62155713dc3207b4fe7b44176afd))

## [0.4.4](https://github.com/u2i/sandbox_case/compare/v0.4.3...v0.4.4) (2026-08-24)


### Bug Fixes

* use start_owner!/2 instead of checkout/2 for the correct owner semantics ([0aa8282](https://github.com/u2i/sandbox_case/commit/0aa8282ca7b0db425963c5c961cf281c77f317f4))

## [0.4.3](https://github.com/u2i/sandbox_case/compare/v0.4.2...v0.4.3) (2026-08-24)


### Bug Fixes

* point [@source](https://github.com/source)_url and changelog links at the current u2i org ([7998221](https://github.com/u2i/sandbox_case/commit/799822196063198072d7d9261bc9a34fee5ad70a))

## [0.4.2] - 2026-08-24

### Fixed

- `checkin/1` now proactively stops mounted `Phoenix.LiveView` processes
  before Ecto rollback, instead of leaving them to the existing
  wait-then-kill orphan sequence. A mounted LiveView is a long-lived
  server, not finishing async work — `await_orphans` doesn't help it
  exit, so it survived to the post-rollback window, where a message
  arriving from an unrelated concurrent test (e.g. a PubSub broadcast
  on a globally-scoped topic) could crash it with a
  `DBConnection.OwnershipError` before `kill_orphans` reaped it.
  LiveView processes are detected generically via the `$initial_call`
  process-dictionary entry Phoenix.LiveView.Channel sets on mount,
  confirmed against the `Phoenix.LiveView` behaviour — no hardcoded
  module reference, and a no-op when `phoenix_live_view` isn't a
  dependency at all. Everything else keeps the existing
  `await_orphans`/`kill_orphans` treatment unchanged.

## [0.4.1] - 2026-06-30

### Fixed

- Fixed a crash in the ownership manager when `sandbox_case` is used with
  `build_conn/1` in `async: false` (shared mode) tests. The
  `Phoenix.Ecto.SQL.Sandbox` plug calls `allow(repo, owner, self())` inline
  during `Phoenix.ConnTest` dispatch; since `ConnTest` runs the plug pipeline
  in the test process, this overwrote the DBConnection ownership manager's
  `{:owner, ref, proxy}` entry with `{:allowed, ref, proxy}`, crashing
  subsequent checkouts with a `MatchError` and failing all later tests in the
  file. Metadata generation (and the `allow` call it triggers) is now skipped
  for `async: false` checkouts, since shared mode already grants all
  processes DB access.

## [0.4.0] - 2026-06-01

### Added

- FunWithFlags is now isolated via a persistence adapter instead of bytecode
  patching, with setup-time validation of the host config.

[0.4.2]: https://github.com/u2i/sandbox_case/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/u2i/sandbox_case/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/u2i/sandbox_case/compare/v0.3.12...v0.4.0
