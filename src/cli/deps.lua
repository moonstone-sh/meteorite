local deps = {}

function deps.new(source)
  local fs = require("cli.fs")
  local shell = require("cli.shell")
  local build_request = require("meteorite.build_request")
  local package_ctx = require("cli.package_context").new(source, fs.read_file)

  local ctx = {
    fs = fs,
    shell = shell,
    package_ctx = package_ctx,
    build_request = build_request,
  }

  function ctx.package_cli_file()
    return package_ctx:package_cli_file()
  end

  function ctx.package_build_file()
    return package_ctx:package_build_file()
  end

  function ctx.package_dev_file()
    return package_ctx:package_dev_file()
  end

  function ctx.package_guard_file()
    return package_ctx:package_guard_file()
  end

  function ctx.candidate_file(paths)
    return package_ctx:candidate_file(paths)
  end

  function ctx.init(print_help)
    return {
      print_help = print_help,
      roots = { install_root = package_ctx.install_root, module_root = package_ctx.module_root },
    }
  end

  function ctx.build(print_help)
    return {
      print_help = print_help,
      current_dir = shell.current_dir,
      read_file = fs.read_file,
      shell_quote = shell.quote,
      package_cli_file = ctx.package_cli_file,
      package_build_file = ctx.package_build_file,
      run_command = shell.run,
      build_request = build_request,
    }
  end

  function ctx.dev()
    return {
      current_dir = shell.current_dir,
      read_file = fs.read_file,
      shell_quote = shell.quote,
      package_cli_file = ctx.package_cli_file,
      package_build_file = ctx.package_build_file,
      package_dev_file = ctx.package_dev_file,
      package_guard_file = ctx.package_guard_file,
      run_command = shell.run,
      build_request = build_request,
    }
  end

  function ctx.doctor()
    return {
      current_dir = shell.current_dir,
      read_file = fs.read_file,
      path_join = fs.path_join,
      shell_quote = shell.quote,
      candidate_file = ctx.candidate_file,
      package_cli_file = ctx.package_cli_file,
      capture_command = shell.capture,
      run_command = shell.run,
      build_request = build_request,
      roots = {
        module_root = package_ctx.module_root,
        install_root = package_ctx.install_root,
        share_root = package_ctx.share_root,
      },
    }
  end

  function ctx.graph()
    return { build_request = build_request }
  end

  function ctx.check(print_help)
    return {
      print_help = print_help,
      build_request = build_request,
      current_dir = shell.current_dir,
      read_file = fs.read_file,
      shell_quote = shell.quote,
      package_cli_file = ctx.package_cli_file,
      run_command = shell.run,
    }
  end

  return ctx
end

return deps
