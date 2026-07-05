# Lua-Based Competitors (Pending)

The integration of additional Lua-based competitors (OpenResty, Lapis, Turbo, Pegasus) is currently **pending** and not wired into the main benchmark orchestrator (`run.sh`).

## Reason for Pause
Meteorite explicitly targets **Lua 5.4**. However, several heavy-weight Lua competitors (like OpenResty, Lapis, and Turbo) rely fundamentally on **LuaJIT** (Lua 5.1 ABI).

While Moonstone supports isolated package environments (and we can technically define `moonstone.toml` with `luajit@2.1` in the competitor subdirectories), managing a benchmark matrix that cross-compiles and orchestrates entirely different Lua runtimes/interpreters mid-flight introduces significant friction and complexity to the build/test pipeline.

To avoid fundamentally altering the project's focus (which is validating Meteorite against native-grade servers on Lua 5.4), these competitors are placed on hold.

## Current Status
- The directories (`openresty/`, `lapis-openresty/`, `lapis-cqueues/`, `turbo/`, `pegasus/`) contain draft implementations of the app suite endpoints.
- The root project safely remains on **Lua 5.4**.
- `bench/run.sh` does not currently dispatch to these variants.
