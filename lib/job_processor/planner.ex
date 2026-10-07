defmodule JobProcessor.Planner do
  @moduledoc """
  Plans a job: parses and validates the request with `JobProcessor.Job`, then orders the
  tasks with `JobProcessor.Sorter`. Called through the public API in `JobProcessor`.
  """

  alias JobProcessor.{Job, JobTask, Script, Sorter}

  @type error :: Ecto.Changeset.t() | Sorter.cycle_error()

  @doc """
  Returns the job's tasks in execution order, or why the job was rejected: an invalid
  request (a changeset) or a dependency cycle.
  """
  @spec plan(map()) :: {:ok, [JobTask.t()]} | {:error, error()}
  def plan(params) do
    with {:ok, %Job{tasks: tasks}} <- Job.parse(params) do
      Sorter.sort(tasks)
    end
  end

  @doc """
  Like `plan/1`, but returns the ordered tasks as a bash script.
  """
  @spec script(map()) :: {:ok, String.t()} | {:error, error()}
  def script(params) do
    with {:ok, tasks} <- plan(params) do
      {:ok, Script.render(tasks)}
    end
  end
end
