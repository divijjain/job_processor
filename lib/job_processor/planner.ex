defmodule JobProcessor.Planner do
  @moduledoc """
  Responsible for planning job execution.
  """

  alias JobProcessor.{Job, JobTask, Script, Sorter}

  @type error :: Ecto.Changeset.t() | Sorter.cycle_error()

  @spec plan(map()) :: {:ok, [JobTask.t()]} | {:error, error()}
  def plan(params) do
    with {:ok, %Job{tasks: tasks}} <- Job.parse(params) do
      Sorter.sort(tasks)
    end
  end

  @spec script(map()) :: {:ok, String.t()} | {:error, error()}
  def script(params) do
    with {:ok, tasks} <- plan(params) do
      {:ok, Script.render(tasks)}
    end
  end
end
