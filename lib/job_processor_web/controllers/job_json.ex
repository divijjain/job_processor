defmodule JobProcessorWeb.JobJSON do
  alias JobProcessor.JobTask

  @doc """
  Renders tasks in execution order.
  """
  @spec create(%{tasks: [JobTask.t()]}) :: %{tasks: [Jason.OrderedObject.t()]}
  def create(%{tasks: tasks}) do
    %{tasks: for(task <- tasks, do: data(task))}
  end

  @doc """
  Renders a dependency cycle.
  """
  @spec cycle(%{cycle: [String.t()], unscheduled: [String.t()]}) :: %{errors: map()}
  def cycle(%{cycle: cycle, unscheduled: unscheduled}) do
    %{
      errors: %{
        type: "cycle",
        detail: "dependency cycle detected",
        cycle: cycle,
        unscheduled: unscheduled
      }
    }
  end

  # Ordered so each task serializes as {"name": ..., "command": ...}, like the input.
  @spec data(JobTask.t()) :: Jason.OrderedObject.t()
  defp data(task), do: Jason.OrderedObject.new(name: task.name, command: task.command)
end
