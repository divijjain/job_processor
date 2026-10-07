defmodule JobProcessor.Job do
  use Ecto.Schema
  import Ecto.Changeset

  alias JobProcessor.JobTask

  @primary_key false
  embedded_schema do
    embeds_many(:tasks, JobTask)
  end

  @type t :: %__MODULE__{tasks: [JobTask.t()]}

  @spec parse(term()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def parse(params) when is_map(params) do
    %__MODULE__{}
    |> changeset(params)
    |> apply_action(:parse)
  end

  def parse(_params) do
    %__MODULE__{}
    |> change()
    |> add_error(:body, "must be an object")
    |> apply_action(:parse)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  defp changeset(job, params) do
    job
    |> cast(params, [])
    |> cast_embed(:tasks)
    |> validate_tasks_given(params)
    |> update_change(:tasks, &validate_unique_names/1)
    |> update_change(:tasks, &validate_dependencies/1)
  end

  @spec validate_tasks_given(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_tasks_given(changeset, params) do
    if Map.has_key?(params, "tasks") or Map.has_key?(params, :tasks),
      do: changeset,
      else: add_error(changeset, :tasks, "can't be blank")
  end

  @spec validate_unique_names([Ecto.Changeset.t()]) :: [Ecto.Changeset.t()]
  defp validate_unique_names(tasks) do
    counts = Enum.frequencies_by(tasks, &get_field(&1, :name))

    Enum.map(tasks, fn task ->
      name = get_field(task, :name)

      if name && counts[name] > 1,
        do: add_error(task, :name, "is used by more than one task"),
        else: task
    end)
  end

  @spec validate_dependencies([Ecto.Changeset.t()]) :: [Ecto.Changeset.t()]
  defp validate_dependencies(tasks) do
    names = MapSet.new(tasks, &get_field(&1, :name))

    Enum.map(tasks, fn task ->
      task
      |> get_field(:requires)
      |> List.wrap()
      |> Enum.reject(&MapSet.member?(names, &1))
      |> Enum.reduce(task, &add_error(&2, :requires, ~s(references unknown task "#{&1}")))
    end)
  end
end
