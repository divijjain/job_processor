defmodule JobProcessorWeb.JobSHTest do
  use ExUnit.Case, async: true

  alias JobProcessorWeb.{JobJSON, JobSH}

  @moduletag :tmp_dir

  defp run(script), do: System.cmd("bash", ["-c", script], stderr_to_stdout: true)

  test "error output is printed literally, never expanded", %{tmp_dir: tmp_dir} do
    marker = Path.join(tmp_dir, "injected")
    hostile = ~s{$(touch #{marker}) `touch #{marker}` it's "quoted" $HOME \\n}
    assigns = %{cycle: [hostile, hostile], unscheduled: [hostile]}

    assert {output, 1} = run(JobSH.cycle(assigns))

    assert output ==
             "job rejected: dependency cycle detected\n#{Jason.encode!(JobJSON.cycle(assigns))}\n"

    refute File.exists?(marker)
  end
end
