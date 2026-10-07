defmodule JobProcessor.SorterTest do
  use ExUnit.Case, async: true

  doctest JobProcessor.Sorter

  alias JobProcessor.{JobTask, Sorter}

  defp task(name, requires \\ []),
    do: %JobTask{name: name, command: "echo #{name}", requires: requires}

  defp names({:ok, tasks}), do: Enum.map(tasks, & &1.name)

  defp cycle!(tasks) do
    assert {:error, {:cycle, %{cycle: cycle, unscheduled: unscheduled}}} = Sorter.sort(tasks)
    assert_closed_loop(cycle, tasks)
    {cycle, unscheduled}
  end

  # Every task comes after all the tasks it requires.
  defp assert_valid_order(sorted) do
    Enum.reduce(sorted, MapSet.new(), fn task, done ->
      for required <- task.requires do
        assert required in done, "#{task.name} ran before its requirement #{required}"
      end

      MapSet.put(done, task.name)
    end)
  end

  # A cycle is reported as a path [t1, t2, ..., t1] where each task requires the next one.
  defp assert_closed_loop(cycle, tasks) do
    requires = Map.new(tasks, &{&1.name, &1.requires})

    assert length(cycle) >= 2
    assert List.first(cycle) == List.last(cycle)
    assert cycle |> Enum.drop(-1) |> Enum.uniq() |> length() == length(cycle) - 1

    for [from, to] <- Enum.chunk_every(cycle, 2, 1, :discard) do
      assert to in requires[from], "#{from} does not require #{to}"
    end
  end

  describe "ordering" do
    test "empty list" do
      assert {:ok, []} = Sorter.sort([])
    end

    test "the example from the spec" do
      tasks = [
        task("task-1"),
        task("task-2", ["task-3"]),
        task("task-3", ["task-1"]),
        task("task-4", ["task-2", "task-3"])
      ]

      assert names(Sorter.sort(tasks)) == ["task-1", "task-3", "task-2", "task-4"]
    end

    test "independent tasks keep input order" do
      assert names(Sorter.sort([task("c"), task("a"), task("b")])) == ["c", "a", "b"]
    end

    test "dependencies move a task later only as far as needed" do
      tasks = [task("a", ["c"]), task("b"), task("c")]
      assert names(Sorter.sort(tasks)) == ["b", "c", "a"]
    end

    test "a chain given in reverse runs in dependency order" do
      tasks = [task("d", ["c"]), task("c", ["b"]), task("b", ["a"]), task("a")]
      assert names(Sorter.sort(tasks)) == ["a", "b", "c", "d"]
    end

    test "diamond: shared requirement runs once, middle tasks keep input order" do
      tasks = [task("d", ["b", "c"]), task("c", ["a"]), task("b", ["a"]), task("a")]
      assert names(Sorter.sort(tasks)) == ["a", "c", "b", "d"]
    end

    test "a task waits for all of its requirements" do
      tasks = [task("z", ["a", "b", "c"]), task("a"), task("b"), task("c")]
      assert names(Sorter.sort(tasks)) == ["a", "b", "c", "z"]
    end

    test "a task that becomes ready runs before later-listed ready tasks" do
      # y is released when z runs, and goes ahead of w because it was listed first.
      tasks = [task("x"), task("y", ["z"]), task("z"), task("w")]
      assert names(Sorter.sort(tasks)) == ["x", "z", "y", "w"]
    end

    test "independent groups interleave by input order" do
      tasks = [task("a2", ["a1"]), task("b1"), task("a1"), task("b2", ["b1"])]
      assert names(Sorter.sort(tasks)) == ["b1", "a1", "a2", "b2"]
    end

    test "returns the original task structs" do
      tasks = [task("b", ["a"]), task("a")]
      assert {:ok, sorted} = Sorter.sort(tasks)
      assert Enum.sort(sorted) == Enum.sort(tasks)
    end
  end

  describe "cycles" do
    test "2-cycle" do
      {cycle, unscheduled} = cycle!([task("a", ["b"]), task("b", ["a"])])

      assert cycle == ["a", "b", "a"]
      assert unscheduled == ["a", "b"]
    end

    test "3-cycle" do
      {cycle, _} = cycle!([task("a", ["c"]), task("b", ["a"]), task("c", ["b"])])

      assert cycle == ["a", "c", "b", "a"]
    end

    test "a task requiring itself" do
      assert {:error, {:cycle, %{cycle: ["a", "a"], unscheduled: ["a"]}}} =
               Sorter.sort([task("a", ["a"])])
    end

    test "tasks downstream of a cycle are unscheduled but not in the cycle" do
      {cycle, unscheduled} = cycle!([task("a", ["b"]), task("b", ["a"]), task("c", ["a"])])

      refute "c" in cycle
      assert unscheduled == ["a", "b", "c"]
    end

    test "a cycle that does not include the first unscheduled task" do
      # x is stuck behind the y <-> z cycle; the walk starts at x but reports only the loop.
      {cycle, unscheduled} = cycle!([task("x", ["y"]), task("y", ["z"]), task("z", ["y"])])

      assert cycle == ["y", "z", "y"]
      assert unscheduled == ["x", "y", "z"]
    end

    test "tasks that can run are not reported as unscheduled" do
      {_, unscheduled} =
        cycle!([task("ok"), task("a", ["b"]), task("b", ["a"]), task("ok2", ["ok"])])

      assert unscheduled == ["a", "b"]
    end

    test "two separate cycles: one is reported, all their tasks are unscheduled" do
      tasks = [task("a", ["b"]), task("b", ["a"]), task("c", ["d"]), task("d", ["c"])]
      {cycle, unscheduled} = cycle!(tasks)

      assert Enum.sort(Enum.uniq(cycle)) in [["a", "b"], ["c", "d"]]
      assert unscheduled == ["a", "b", "c", "d"]
    end
  end

  describe "random jobs compared with a reference implementation" do
    # The reference is the definition of the expected order: repeatedly run the first task,
    # in input order, whose requirements have all run. It is O(n^2), so only used here.
    defp reference_sort(tasks), do: reference_sort(tasks, MapSet.new(), [])

    defp reference_sort(remaining, done, sorted) do
      case Enum.find(remaining, fn task -> Enum.all?(task.requires, &(&1 in done)) end) do
        nil ->
          {Enum.reverse(sorted), remaining}

        task ->
          reference_sort(List.delete(remaining, task), MapSet.put(done, task.name), [
            task | sorted
          ])
      end
    end

    # Builds n tasks listed in a shuffled order. With `acyclic: true`, tasks only require
    # tasks earlier in a hidden order, so there can be no cycle; otherwise any edge is allowed.
    defp random_job(n, acyclic: acyclic) do
      names = Enum.map(1..n//1, &"t#{&1}")

      names
      |> Enum.with_index()
      |> Enum.map(fn {name, i} ->
        candidates = if acyclic, do: Enum.take(names, i), else: names -- [name]
        task(name, Enum.filter(candidates, fn _ -> :rand.uniform() < 0.3 end))
      end)
      |> Enum.shuffle()
    end

    for seed <- 1..300 do
      @seed seed
      test "seed #{seed}" do
        :rand.seed(:exsss, @seed)
        tasks = random_job(:rand.uniform(12) - 1, acyclic: rem(@seed, 2) == 0)

        case reference_sort(tasks) do
          {sorted, []} ->
            assert {:ok, ^sorted} = Sorter.sort(tasks)
            assert_valid_order(sorted)

          {_, stuck} ->
            {cycle, unscheduled} = cycle!(tasks)
            assert unscheduled == Enum.map(stuck, & &1.name)
            assert Enum.all?(cycle, &(&1 in unscheduled))
        end
      end
    end
  end

  describe "large jobs" do
    # Sizes where an accidental O(n^2) step would take minutes and hit the test timeout,
    # while the O(n log n) sort finishes in well under a second.
    @n 50_000

    test "a long chain given in reverse" do
      tasks = for i <- @n..1//-1, do: task("t#{i}", if(i > 1, do: ["t#{i - 1}"], else: []))

      assert {:ok, sorted} = Sorter.sort(tasks)
      assert names({:ok, sorted}) == for(i <- 1..@n, do: "t#{i}")
    end

    test "many tasks requiring one shared task listed last" do
      tasks = for(i <- 1..@n, do: task("t#{i}", ["root"])) ++ [task("root")]

      assert {:ok, [%JobTask{name: "root"} | rest]} = Sorter.sort(tasks)
      assert names({:ok, rest}) == for(i <- 1..@n, do: "t#{i}")
    end

    test "a long cycle" do
      tasks = for i <- 1..@n, do: task("t#{i}", ["t#{rem(i, @n) + 1}"])

      {cycle, unscheduled} = cycle!(tasks)
      assert length(cycle) == @n + 1
      assert length(unscheduled) == @n
    end
  end
end
