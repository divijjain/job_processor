defmodule JobProcessorWeb.JobController do
  @moduledoc """
  Plans jobs: `POST /jobs` and `POST /jobs/script`.

  Responds with JSON or a bash script, depending on the format the router negotiated.
  Errors are handled by `JobProcessorWeb.FallbackController`.
  """
  use JobProcessorWeb, :controller

  plug :put_view,
    json: JobProcessorWeb.JobJSON,
    sh: JobProcessorWeb.JobSH,
    txt: JobProcessorWeb.JobSH

  action_fallback JobProcessorWeb.FallbackController

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, JobProcessor.Planner.error()}
  def create(conn, params) do
    with {:ok, tasks} <- JobProcessor.plan(params) do
      render(conn, :create, tasks: tasks)
    end
  end
end
