defmodule JobProcessor.Sorter do
  @moduledoc """
  Orders tasks so each runs after the tasks it requires.

  The sort is stable: tasks keep their input order unless a dependency forces them later.
  """

  alias JobProcessor.JobTask

  @typedoc "The loop as a path where each task requires the next, plus every task left unscheduled."
  @type cycle_error :: {:cycle, %{cycle: [String.t()], unscheduled: [String.t()]}}

  # Tasks are referred to by their position in the input list.
  @typep position :: non_neg_integer()

  @typep graph :: %{
           tasks: tuple(),
           positions: %{String.t() => position()},
           requirements_left: %{position() => non_neg_integer()},
           dependents: %{position() => [position()]}
         }

  # Positions whose requirements have all run; take_smallest gives the earliest-listed one.
  @typep ready :: :gb_sets.set(position())

  @doc """
  Returns the tasks in execution order, or the tasks that form a cycle.

  ## Examples

      iex> alias JobProcessor.JobTask
      iex> tasks = [
      ...>   %JobTask{name: "task-1", command: "touch /tmp/file1"},
      ...>   %JobTask{name: "task-2", command: "cat /tmp/file1", requires: ["task-3"]},
      ...>   %JobTask{name: "task-3", command: "echo hi > /tmp/file1", requires: ["task-1"]},
      ...>   %JobTask{name: "task-4", command: "rm /tmp/file1", requires: ["task-2", "task-3"]}
      ...> ]
      iex> {:ok, sorted} = JobProcessor.Sorter.sort(tasks)
      iex> Enum.map(sorted, & &1.name)
      ["task-1", "task-3", "task-2", "task-4"]
  """
  @spec sort([JobTask.t()]) :: {:ok, [JobTask.t()]} | {:error, cycle_error()}
  def sort(tasks) do
    graph = build_graph(tasks)

    graph
    |> schedule()
    |> to_result(graph)
  end

  # -- Graph ----------------------------------------------------------------

  @spec build_graph([JobTask.t()]) :: graph()
  defp build_graph(tasks) do
    indexed_tasks = Enum.with_index(tasks)

    positions = Map.new(indexed_tasks, fn {task, i} -> {task.name, i} end)

    requirements =
      for {task, i} <- indexed_tasks, name <- task.requires, do: {Map.fetch!(positions, name), i}

    dependents =
      Enum.group_by(requirements, fn {required, _} -> required end, fn {_, i} -> i end)

    %{
      tasks: List.to_tuple(tasks),
      positions: positions,
      requirements_left: Map.new(indexed_tasks, fn {task, i} -> {i, length(task.requires)} end),
      dependents: dependents
    }
  end

  # -- Scheduling (Kahn's algorithm, always taking the earliest ready task) ----

  # Returns the positions of every task that could be scheduled, in execution order.
  # Tasks in or behind a cycle never become ready, so they are missing from the result.
  @spec schedule(graph()) :: [position()]
  defp schedule(graph) do
    ready = :gb_sets.from_list(for {i, 0} <- graph.requirements_left, do: i)
    drain(ready, graph.requirements_left, graph.dependents, [])
  end

  @spec drain(ready(), %{position() => non_neg_integer()}, %{position() => [position()]}, [
          position()
        ]) :: [position()]
  defp drain(ready, requirements_left, dependents, order) do
    if :gb_sets.is_empty(ready) do
      Enum.reverse(order)
    else
      {i, ready} = :gb_sets.take_smallest(ready)

      {ready, requirements_left} =
        dependents
        |> Map.get(i, [])
        |> Enum.reduce({ready, requirements_left}, &release/2)

      drain(ready, requirements_left, dependents, [i | order])
    end
  end

  # One of `i`'s requirements has been scheduled; `i` is ready once none are left.
  @spec release(position(), {ready(), %{position() => non_neg_integer()}}) ::
          {ready(), %{position() => non_neg_integer()}}
  defp release(i, {ready, requirements_left}) do
    case Map.fetch!(requirements_left, i) - 1 do
      0 -> {:gb_sets.add(i, ready), Map.put(requirements_left, i, 0)}
      left -> {ready, Map.put(requirements_left, i, left)}
    end
  end

  @spec to_result([position()], graph()) :: {:ok, [JobTask.t()]} | {:error, cycle_error()}
  defp to_result(order, graph) when length(order) == tuple_size(graph.tasks) do
    {:ok, Enum.map(order, &elem(graph.tasks, &1))}
  end

  defp to_result(order, graph), do: cycle_error(order, graph)

  # -- Cycle detection ------------------------------------------------------

  @spec cycle_error([position()], graph()) :: {:error, cycle_error()}
  defp cycle_error(order, graph) do
    scheduled = MapSet.new(order)
    all = 0..(tuple_size(graph.tasks) - 1)//1
    unscheduled = Enum.reject(all, &MapSet.member?(scheduled, &1))
    cycle = find_cycle(unscheduled, scheduled, graph)

    {:error, {:cycle, %{cycle: names(cycle, graph), unscheduled: names(unscheduled, graph)}}}
  end

  # Every unscheduled task has a requirement that is also unscheduled (otherwise it would
  # have become ready). Following those requirements from any unscheduled task must
  # therefore revisit a task, and the path from that task back to itself is a cycle.
  @spec find_cycle([position(), ...], MapSet.t(position()), graph()) :: [position(), ...]
  defp find_cycle([start | _] = unscheduled, scheduled, graph) do
    next = Map.new(unscheduled, &{&1, unscheduled_requirement(&1, scheduled, graph)})
    walk(start, next, [], %{})
  end

  @spec unscheduled_requirement(position(), MapSet.t(position()), graph()) :: position()
  defp unscheduled_requirement(i, scheduled, graph) do
    elem(graph.tasks, i).requires
    |> Enum.map(&Map.fetch!(graph.positions, &1))
    |> Enum.find(&(not MapSet.member?(scheduled, &1)))
  end

  # On reaching a task already visited, the cycle is the path from its first visit on.
  @spec walk(position(), %{position() => position()}, [position()], %{
          position() => non_neg_integer()
        }) :: [position(), ...]
  defp walk(i, next, path, visited_at) do
    case visited_at do
      %{^i => step} ->
        path |> Enum.reverse() |> Enum.drop(step) |> Enum.concat([i])

      _ ->
        walk(Map.fetch!(next, i), next, [i | path], Map.put(visited_at, i, map_size(visited_at)))
    end
  end

  @spec names([position()], graph()) :: [String.t()]
  defp names(positions, graph), do: Enum.map(positions, &elem(graph.tasks, &1).name)
end
