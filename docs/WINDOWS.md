# Windows service contract

Meteorite separates host operations with Moonstone flavors: `cli.shell`,
`cli.dev_host` and `ballad.release_host` select their Windows implementations.
The Windows supervisor comes from Clingy's Job Object backend. Source workers
retain both ordinary and versioned Lua module paths.

The native Windows x64 workflow covers project scaffolding, PUC Lua compilation
without Make, and static/hybrid servers on `std_http` and `fast_http`. It checks
HTTP responses, executes relocated binaries, and cancels an idle accept loop.
The direct dev contract also starts a server, edits an inline Lua handler,
checks the refreshed response and retires the process tree.

Service installation uses Zig file operations rather than `sh`, `cp` or
`mkdir`. Windows console shutdown uses a bounded AFD poll on Zig's native socket
handle. Dev event files use append access so writes do not overwrite existing
supervisor events.

Windows-host cross-target C-module rebuilding remains unsupported and fails
before scheduling a POSIX build script. Use target-built compatible modules or
a supported POSIX build host. Unix-socket credential transports are outside the
Windows TCP certification matrix. External capabilities and native dependencies
still require their own platform acceptance tests.

The package rollout is ordered: Moonstone fixes, portable Ballad, Clingy, then
Meteorite's dependency updates. The feature CI uses the companion source
checkouts while those releases are pending. It does not prove that old registry
artifacts already have the new Windows interfaces.
