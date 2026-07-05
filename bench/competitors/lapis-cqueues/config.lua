local config = require("lapis.config")

config({"development", "production"}, {
  port = os.getenv("PORT") or 8080,
  server = "cqueues",
  logging = {
    queries = false,
    requests = false
  }
})
