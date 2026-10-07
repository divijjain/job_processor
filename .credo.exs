# Credo's defaults, with one change: modules that `use Ecto.Schema` still need a @moduledoc.
# By default Credo skips them, assuming database tables; here the embedded schemas
# (JobProcessor.Job, JobProcessor.JobTask) hold the request validation rules.
%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {Credo.Check.Readability.ModuleDoc,
           ignore_modules_using: [Credo.Check, Phoenix.LiveView, ~r/\.Web$/]}
        ]
      }
    }
  ]
}
