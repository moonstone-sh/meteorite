local ballad = require("ballad")

return ballad.partiture(function(p)
  local meteorite = p:use("meteorite.ballad")
  local release = meteorite.release({
    input = "src/main.lua",
    output = ".meteorite/release/ipc-native/server",
    graph_output = ".meteorite/graph/ipc-native-release",
    mode = "hybrid",
    backend = "ipc_unixsocket",
    hybrid_profile = "default",
    unix_socket_path = "/tmp/meteorite-ipc-native-release.sock",
    unix_socket_mode = "0660",
    unix_socket_unlink_stale = true,
  })
  p.sink.directory(release, { out = "dist/release", file_graph = true, product = "release" })
end)
