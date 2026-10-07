defmodule JobProcessorWeb.Router do
  use JobProcessorWeb, :router

  # JSON by default. A bash script for `Accept: text/x-shellscript` (or another shell type),
  # `Accept: text/plain` (sent as text/plain), or `?format=sh`.
  pipeline :api do
    plug :format_param
    plug :accepts, ["json", "sh", "txt"]
  end

  pipeline :script do
    plug :format_param
    plug :accepts, ["sh", "txt"]
  end

  scope "/", JobProcessorWeb do
    pipe_through :api
    post "/jobs", JobController, :create
  end

  scope "/", JobProcessorWeb do
    pipe_through :script
    post "/jobs/script", JobController, :create
  end

  @format_aliases %{"sh" => "sh", "bash" => "sh", "json" => "json"}

  # Phoenix picks the format from `?_format=`; also accept the more common `?format=`,
  # with `bash` as another name for `sh`. Other values pass through, so `:accepts`
  # answers 406 instead of silently falling back to the Accept header.
  defp format_param(%{params: %{"format" => format}} = conn, _opts) when is_binary(format) do
    %{conn | params: Map.put(conn.params, "_format", Map.get(@format_aliases, format, format))}
  end

  defp format_param(conn, _opts), do: conn
end
