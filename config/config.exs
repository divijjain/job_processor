# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :job_processor,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :job_processor, JobProcessorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: JobProcessorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JobProcessor.PubSub,
  live_view: [signing_salt: "IPqavdZp"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Bash scripts are the "sh" format. `mime` already maps "sh" to application/x-sh; this adds
# the other shell script types clients send, and makes text/x-shellscript the content type
# sent with scripts. (Clients asking for text/plain get the script as the "txt" format.)
config :mime,
  types: %{
    "text/x-shellscript" => ["sh"],
    "text/x-sh" => ["sh"],
    "application/x-shellscript" => ["sh"]
  },
  extensions: %{"sh" => "text/x-shellscript"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
