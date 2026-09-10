# Development session ownership

`meteorite dev` uses Clingy's process supervisor. Meteorite still decides when to
generate the graph, reload Lua handlers, rebuild, and restart the server. Clingy
owns the worker, compiler and server process group until shutdown completes.

Press Ctrl-C or Ctrl-D in the terminal to stop the session. SIGTERM, SIGHUP,
worker failure and loss of the launching parent also stop the owned group.
Redirected stdin is supported without treating its EOF as a stop request.
The browser may retain an already-rendered page, but the server listener closes.

The package launcher performs Lua preflight, then execs a Bash supervisor. It
requires Clingy 0.5.0 and Bash 3.2 or later on macOS/Linux. Prefer the package
launcher to `lua src/cli/main.lua dev`: Lua's synchronous command execution can
ignore a SIGINT sent only to the Lua PID, although terminal group signals and
parent death are handled by the external supervisor.

The repository's Ballad watcher follows the same contract through `moon run dev`
or `sh scripts/watch.sh --mode hybrid_dev --backend fast_http`. Direct execution
of `Watch_partiture.lua` or `src/cli/dev.lua` without a session owner is rejected.
Ballad retains ownership of build caching and source reactions.

Each project takes `.meteorite/dev/session.lock`. A second session fails instead
of terminating another project or reclaiming a port. Server PID records include
the active session owner's PID and are used only within that session. Shutdown
does not scan names or ports to choose processes to kill. The old `guard.sh` is
an explicit recovery utility, no longer part of automatic startup or shutdown.

If the owner itself receives SIGKILL, cleanup cannot execute. Inspect the lock's
`owner.pid` and any surviving process group before removing a stale lock.
Children that deliberately leave their inherited group are outside this backend's
contract. Development servers and compiler children must not daemonize.
