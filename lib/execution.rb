require 'open3'

# Wrapper around open3.popen2e which fails on error
#
# We emulate open3.capture2e with the following changes in behavior:
# 1) The command is printed to stdout before execution.
# 2) Attempts to use the shell implicitly are blocked.
# 3) Nonzero return codes result in the process exiting.
#
# If you're looking for more process/stream control read the spawn documentation, and pass
# options directly here
def fail_on_error (*cmd, **opts)
#  puts "Running Command: \n#{debug_print_cmd_list([cmd])}\n"
  shell_safe(cmd)
  output, status = Open3.capture2(*cmd, opts)
  exit_on_status(output, status)
end

# Look at a cmd list intended for spawn.
# determine if spawn will call the shell implicitly, fail in that case.
def shell_safe (cmd)
  # env and opts in the command spec both aren't of type string.
  # If you're only passing one string, spawn is going to launch a shell.
  if cmd.select{ |element| element.class == String }.length == 1
    puts "You tried to use sqiosbuild to call the shell implicitly. Please don't."
    puts "Think of the children."
    puts "Think of shellshock."
    puts "Please don't. Not ever."
    exit 1
  end
end

def debug_print_cmd_list(cmd_list)
  # Take a list of command argument lists like you'd sent to open3.pipeline or fail_on_error_pipe and
  # print out a string that would do the same thing when entered at the shell.
  #
  # This is a converter from our internal representation of commands to a subset of bash that
  # can be executed directly.
  #
  # Note this has problems if you specify env or opts
  # TODO: make this remove those command parts
  "\"" +
  cmd_list.map { |cmd|
    cmd.map { |arg|
      arg.gsub("\"", "\\\"") # Escape all double quotes in command arguments
    }.join("\" \"") # Fully quote all command parts. We add quotes to the beginning and end too.
  }.join("\" | \"") + # Pipe commands to one another.
  "\""
end

# If any of the statuses are bad, exits with the
# return code of the first one.
#
# Otherwise returns first argument (output)
def exit_on_status (output, status)
  # Do nothing for proper statuses
  if status.exited? && status.exitstatus == 0
    return output
  end

  # If we exited nonzero or abnormally, print debugging info
  # and explode.
  if status.exited?
    puts "Return code was #{status.exitstatus}"
    exit status.exitstatus
  end
  puts "This might be helpful:\nProcessStatus: #{status.inspect}\nRaw POSIX Status: #{status.to_i}\n"
  exit 1
end


