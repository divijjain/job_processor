defmodule JobProcessor.JobTask do
  @moduledoc """
  A single task in a job: a `name`, a shell `command`, and the names of the tasks it
  `requires` to have run first.

  An embedded schema (no database), cast and validated as part of `JobProcessor.Job`.
  Rules checked here, on the task alone:

    * `name` and `command` are required, non-blank strings
    * `requires` is a list of strings; `null` means none, and duplicates are removed
    * a task cannot require itself

  Rules that involve other tasks (unique names, known requirements) are in
  `JobProcessor.Job`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:command, :string)
    field(:requires, {:array, :string}, default: [])
  end

  @type t :: %__MODULE__{name: String.t(), command: String.t(), requires: [String.t()]}

  @doc """
  Casts and validates one task's params. Called by `Ecto.Changeset.cast_embed/3` from
  `JobProcessor.Job`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, params) do
    task
    |> cast(params, [:name, :command, :requires])
    |> validate_required([:name, :command])
    |> update_change(:requires, &if(&1, do: Enum.uniq(&1), else: []))
    |> validate_not_self_dependent()
  end

  @spec validate_not_self_dependent(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_not_self_dependent(changeset) do
    name = get_field(changeset, :name)

    validate_change(changeset, :requires, fn :requires, reqs ->
      if name in reqs, do: [requires: "cannot include the task itself"], else: []
    end)
  end
end
