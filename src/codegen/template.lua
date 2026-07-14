--- Compatibility shim for older codegen imports.
--- Public app code should prefer `require("meteorite").template`.

return require("core.template")
