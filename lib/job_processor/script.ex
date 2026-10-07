defmodule JobProcessor.Script do
  @moduledoc """
  Renders ordered tasks as a bash script.
  """

  alias JobProcessor.JobTask

  @doc """
  Returns a bash script that runs the tasks' commands in the given order.

  The format matches the challenge's expected output exactly: a shebang, then one
  command per line, each exactly as given.

  ## Examples

      iex> JobProcessor.Script.render([
      ...>   %JobProcessor.JobTask{name: "a", command: "touch /tmp/file1"},
      ...>   %JobProcessor.JobTask{name: "b", command: "cat /tmp/file1"}
      ...> ])
      "#!/usr/bin/env bash\\ntouch /tmp/file1\\ncat /tmp/file1\\n"
  """
  @spec render([JobTask.t()]) :: String.t()
  def render(tasks) do
    Enum.map_join(["#!/usr/bin/env bash" | Enum.map(tasks, & &1.command)], &[&1, "\n"])
  end
end
