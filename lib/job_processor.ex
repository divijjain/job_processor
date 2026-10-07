defmodule JobProcessor do
  @moduledoc """
  Public API for planning job execution. Delegates only.
  """

  alias JobProcessor.Planner

  @doc "Validates a job and returns its tasks in execution order."
  @spec plan(map()) :: {:ok, [JobProcessor.JobTask.t()]} | {:error, Planner.error()}
  defdelegate plan(params), to: Planner

  @doc "Validates a job and returns it as a bash script."
  @spec script(map()) :: {:ok, String.t()} | {:error, Planner.error()}
  defdelegate script(params), to: Planner
end
