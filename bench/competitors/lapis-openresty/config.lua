local config = require("lapis.config")
config("production", {
  port = os.getenv("PORT") or 8080,
  num_workers = 1,
  code_cache = "on",
  daemon = "off"
})
