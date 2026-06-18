return function(c)
  local cruncher = c:zig("data_cruncher")

  return c:json({
    device = cruncher.device_name(c.params.device_id),
  })
end
