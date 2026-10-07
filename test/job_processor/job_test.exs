defmodule JobProcessor.JobTest do
  use ExUnit.Case, async: true

  alias JobProcessor.{Job, JobTask}

  defp errors(params) do
    assert {:error, changeset} = Job.parse(params)
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp task(name, attrs \\ %{}),
    do: Map.merge(%{"name" => name, "command" => "echo #{name}"}, attrs)

  describe "valid jobs" do
    test "parses tasks into structs, defaulting requires to []" do
      params = %{"tasks" => [task("a"), task("b", %{"requires" => ["a"]})]}

      assert {:ok,
              %Job{
                tasks: [
                  %JobTask{name: "a", command: "echo a", requires: []},
                  %JobTask{name: "b", command: "echo b", requires: ["a"]}
                ]
              }} = Job.parse(params)
    end

    test "accepts atom keys" do
      assert {:ok, %Job{tasks: [%JobTask{name: "a"}]}} =
               Job.parse(%{tasks: [%{name: "a", command: "echo a"}]})
    end

    test "accepts an empty task list" do
      assert {:ok, %Job{tasks: []}} = Job.parse(%{"tasks" => []})
    end

    test "treats requires: null as no requirements" do
      assert {:ok, %Job{tasks: [%JobTask{requires: []}]}} =
               Job.parse(%{"tasks" => [task("a", %{"requires" => nil})]})
    end

    test "removes duplicate requirements" do
      params = %{"tasks" => [task("a"), task("b", %{"requires" => ["a", "a"]})]}

      assert {:ok, %Job{tasks: [_, %JobTask{requires: ["a"]}]}} = Job.parse(params)
    end
  end

  describe "malformed bodies" do
    test "rejects a body that is not an object" do
      assert errors([1]) == %{body: ["must be an object"]}
      assert errors("tasks") == %{body: ["must be an object"]}
    end

    test "requires tasks" do
      assert errors(%{}) == %{tasks: ["can't be blank"]}
    end

    test "rejects tasks that are null or not a list of objects" do
      assert errors(%{"tasks" => nil}) == %{tasks: ["is invalid"]}
      assert errors(%{"tasks" => "a"}) == %{tasks: ["is invalid"]}
      assert errors(%{"tasks" => ["a"]}) == %{tasks: ["is invalid"]}
    end
  end

  describe "task fields" do
    test "requires a name and a command" do
      assert errors(%{"tasks" => [%{}]}) == %{
               tasks: [%{name: ["can't be blank"], command: ["can't be blank"]}]
             }
    end

    test "treats empty strings as blank" do
      assert errors(%{"tasks" => [%{"name" => "", "command" => ""}]}) == %{
               tasks: [%{name: ["can't be blank"], command: ["can't be blank"]}]
             }
    end

    test "rejects fields of the wrong type" do
      params = %{"tasks" => [%{"name" => 1, "command" => "c", "requires" => "b"}]}

      assert errors(params) == %{tasks: [%{name: ["is invalid"], requires: ["is invalid"]}]}
    end
  end

  describe "dependencies between tasks" do
    test "rejects a task that requires itself" do
      assert errors(%{"tasks" => [task("a", %{"requires" => ["a"]})]}) == %{
               tasks: [%{requires: ["cannot include the task itself"]}]
             }
    end

    test "rejects duplicate names on every task that uses them" do
      params = %{"tasks" => [task("a"), task("a"), task("b")]}

      assert errors(params) == %{
               tasks: [
                 %{name: ["is used by more than one task"]},
                 %{name: ["is used by more than one task"]},
                 %{}
               ]
             }
    end

    test "reports each unknown requirement on the task that has it" do
      params = %{"tasks" => [task("a"), task("b", %{"requires" => ["a", "x", "y"]})]}

      assert %{tasks: [%{}, %{requires: requires}]} = errors(params)

      assert Enum.sort(requires) == [
               ~s(references unknown task "x"),
               ~s(references unknown task "y")
             ]
    end
  end
end
