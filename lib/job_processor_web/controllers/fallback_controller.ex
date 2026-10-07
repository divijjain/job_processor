defmodule JobProcessorWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use JobProcessorWeb, :controller

  alias JobProcessorWeb.{ChangesetJSON, JobJSON, JobSH}

  @spec call(Plug.Conn.t(), {:error, JobProcessor.Planner.error()}) :: Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ChangesetJSON, sh: JobSH, txt: JobSH)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, {:cycle, %{cycle: _, unscheduled: _} = details}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: JobJSON, sh: JobSH, txt: JobSH)
    |> render(:cycle, details)
  end
end
