defmodule JobProcessorWeb.ChangesetJSON do
  @doc """
  Renders changeset errors, keyed by field, alongside the error `type` and `detail`.
  """
  @spec error(%{changeset: Ecto.Changeset.t()}) :: %{errors: map()}
  def error(%{changeset: changeset}) do
    errors = Ecto.Changeset.traverse_errors(changeset, &translate_error/1)

    %{errors: Map.merge(errors, %{type: "validation", detail: "validation failed"})}
  end

  @spec translate_error({String.t(), keyword()}) :: String.t()
  defp translate_error({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts
      |> Keyword.get(String.to_existing_atom(key), key)
      |> to_display()
    end)
  end

  @spec to_display(term()) :: String.t()
  defp to_display(value) when is_list(value), do: Enum.map_join(value, ", ", &to_string/1)
  defp to_display(value), do: to_string(value)
end
