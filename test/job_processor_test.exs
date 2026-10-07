defmodule JobProcessorTest do
  use ExUnit.Case, async: true

  alias JobProcessor.JobTask

  @job %{
    "tasks" => [
      %{"name" => "b", "command" => "echo b", "requires" => ["a"]},
      %{"name" => "a", "command" => "echo a"}
    ]
  }

  @cycle %{
    "tasks" => [
      %{"name" => "a", "command" => "echo a", "requires" => ["b"]},
      %{"name" => "b", "command" => "echo b", "requires" => ["a"]}
    ]
  }

  describe "plan/1" do
    test "returns tasks in execution order" do
      assert {:ok, [%JobTask{name: "a"}, %JobTask{name: "b"}]} = JobProcessor.plan(@job)
    end

    test "returns validation errors" do
      assert {:error, %Ecto.Changeset{}} = JobProcessor.plan(%{})
    end

    test "returns cycles" do
      assert {:error, {:cycle, %{unscheduled: ["a", "b"]}}} = JobProcessor.plan(@cycle)
    end
  end

  describe "script/1" do
    test "returns the job as a bash script" do
      assert JobProcessor.script(@job) == {:ok, "#!/usr/bin/env bash\necho a\necho b\n"}
    end

    test "returns validation errors" do
      assert {:error, %Ecto.Changeset{}} = JobProcessor.script(%{})
    end

    test "returns cycles" do
      assert {:error, {:cycle, _}} = JobProcessor.script(@cycle)
    end
  end
end
