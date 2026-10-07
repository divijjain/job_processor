defmodule JobProcessorWeb.JobSH do
  @moduledoc """
  Renders jobs as bash scripts (the "sh" format).

  Errors are scripts too, because clients may pipe the response straight into bash:
  they print the same body the JSON format would send and exit 1, running nothing.
  """

  alias JobProcessor.{JobTask, Script}
  alias JobProcessorWeb.{ChangesetJSON, JobJSON}

  @doc """
  Renders tasks in execution order as a script.
  """
  @spec create(%{tasks: [JobTask.t()]}) :: String.t()
  def create(%{tasks: tasks}), do: Script.render(tasks)

  @doc """
  Renders changeset errors as a failing script.
  """
  @spec error(%{changeset: Ecto.Changeset.t()}) :: String.t()
  def error(assigns), do: rejected(ChangesetJSON.error(assigns))

  @doc """
  Renders a dependency cycle as a failing script.
  """
  @spec cycle(%{cycle: [String.t()], unscheduled: [String.t()]}) :: String.t()
  def cycle(assigns), do: rejected(JobJSON.cycle(assigns))

  # The error may echo request input (such as task names), so every value is
  # single-quoted: nothing in it is expanded or executed.
  @spec rejected(%{errors: %{:detail => String.t(), optional(atom()) => term()}}) ::
          String.t()
  defp rejected(%{errors: %{detail: message}} = body) do
    """
    #!/usr/bin/env bash
    #{print_to_stderr("job rejected: " <> message)}
    #{print_to_stderr(Jason.encode!(body))}
    exit 1
    """
  end

  @spec print_to_stderr(String.t()) :: String.t()
  defp print_to_stderr(text), do: "printf '%s\\n' #{single_quote(text)} >&2"

  # Inside single quotes bash expands nothing; a literal ' is written as '\'' (close,
  # escaped quote, reopen).
  @spec single_quote(String.t()) :: String.t()
  defp single_quote(text), do: "'" <> String.replace(text, "'", ~S('\'')) <> "'"
end
