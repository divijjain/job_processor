defmodule JobProcessor.JobTask do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:command, :string)
    field(:requires, {:array, :string}, default: [])
  end

  @type t :: %__MODULE__{name: String.t(), command: String.t(), requires: [String.t()]}

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
