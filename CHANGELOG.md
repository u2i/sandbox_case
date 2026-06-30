# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.4.1]: https://github.com/pinetops/sandbox_case/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/pinetops/sandbox_case/compare/v0.3.12...v0.4.0
