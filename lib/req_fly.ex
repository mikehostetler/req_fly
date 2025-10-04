defmodule ReqFly do
  @moduledoc """
  A Req plugin for the Fly.io Machines API.

  ReqFly provides a convenient interface to interact with Fly.io's Machines API
  through the Req HTTP client library. It handles authentication, error handling,
  retries, and telemetry automatically.

  ## Installation

  Add ReqFly to your dependencies in `mix.exs`:

      def deps do
        [
          {:req_fly, "~> 0.1.0"}
        ]
      end

  ## Quick Start

  Get your API token from https://fly.io/user/personal_access_tokens:

      req = Req.new() |> ReqFly.attach(token: "your_fly_token")

      # List apps
      {:ok, apps} = ReqFly.Apps.list(req, org_slug: "personal")

      # Create a machine
      {:ok, machine} = ReqFly.Machines.create(req,
        app_name: "my-app",
        config: %{image: "nginx:latest"}
      )

  ## High-Level APIs

  ReqFly provides convenient helper modules for common operations:

    * `ReqFly.Apps` - Create and manage Fly.io applications
    * `ReqFly.Machines` - Full machine lifecycle management
    * `ReqFly.Secrets` - Manage application secrets
    * `ReqFly.Volumes` - Persistent storage operations
    * `ReqFly.Orchestrator` - Multi-step workflows with polling

  ## Low-Level Plugin Usage

  You can also use ReqFly as a Req plugin with direct HTTP calls:

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, %{body: apps}} = Req.get(req, url: "/apps", params: [org_slug: "personal"])
      {:ok, %{body: app}} = Req.post(req, url: "/apps", json: %{app_name: "test", org_slug: "personal"})

  ## Configuration

  ### Explicit Token (Recommended)

      req = Req.new() |> ReqFly.attach(token: "your_fly_token")

  ### Environment Variable

      req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

  ### Application Config

      # config/config.exs
      config :req_fly, token: "your_fly_token"

      # In your code
      req = Req.new() |> ReqFly.attach()

  ### Runtime Config (Recommended for Production)

      # config/runtime.exs
      config :req_fly, token: System.get_env("FLY_API_TOKEN")

  ## Options

    * `:token` - Your Fly.io API token (required, can be set in app config)
    * `:base_url` - Override the default API base URL (default: "https://api.machines.dev/v1")
    * `:retry` - Retry strategy (default: `:safe_transient`)
    * `:max_retries` - Maximum number of retries (default: 3)
    * `:telemetry_prefix` - Custom telemetry event prefix (default: `[:req_fly]`)

  ## Authentication

  Get your API token from: https://fly.io/user/personal_access_tokens

  **Important:** Never commit your API token to version control. Use environment
  variables or runtime configuration.

  ## Telemetry

  ReqFly emits the following telemetry events:

    * `[:req_fly, :request, :start]` - Emitted when a request starts
    * `[:req_fly, :request, :stop]` - Emitted when a request completes successfully
    * `[:req_fly, :request, :exception]` - Emitted when a request fails

  You can attach handlers to monitor your API usage:

      :telemetry.attach_many(
        "req-fly-handler",
        [
          [:req_fly, :request, :start],
          [:req_fly, :request, :stop],
          [:req_fly, :request, :exception]
        ],
        fn event_name, measurements, metadata, _config ->
          # Handle telemetry event
          Logger.info("Fly.io API call", event: event_name, metadata: metadata)
        end,
        nil
      )

  ## Examples

      # Basic usage with token
      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, apps} = ReqFly.Apps.list(req, org_slug: "personal")

      # Create app and machine
      req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))
      {:ok, app} = ReqFly.Apps.create(req, app_name: "my-app", org_slug: "personal")
      
      config = %{
        image: "nginx:latest",
        guest: %{cpus: 1, memory_mb: 256}
      }
      {:ok, machine} = ReqFly.Machines.create(req, app_name: "my-app", config: config)

      # Use orchestrator for complex workflows
      {:ok, machine} = ReqFly.Orchestrator.create_machine_and_wait(req,
        app_name: "my-app",
        config: config,
        timeout: 60
      )

      # Custom retry configuration
      req = Req.new() |> ReqFly.attach(
        token: "fly_token",
        retry: :transient,
        max_retries: 5
      )

      # Custom telemetry prefix
      req = Req.new() |> ReqFly.attach(
        token: "fly_token",
        telemetry_prefix: [:my_app, :fly]
      )

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, %ReqFly.Error{}}` tuples.
  Use pattern matching to handle errors:

      case ReqFly.Apps.get(req, "my-app") do
        {:ok, app} -> 
          IO.puts("Found app: \#{app["name"]}")
        
        {:error, %ReqFly.Error{status: 404}} ->
          IO.puts("App not found")
        
        {:error, %ReqFly.Error{status: status, message: message}} ->
          IO.puts("Error \#{status}: \#{message}")
      end

  """

  alias ReqFly.Steps

  @default_base_url "https://api.machines.dev/v1"

  @doc """
  Attaches the ReqFly plugin to a Req request.

  ## Options

    * `:token` - Fly.io API token (required if not configured globally)
    * `:base_url` - API base URL (default: "https://api.machines.dev/v1")
    * `:retry` - Retry strategy (default: `:safe_transient`)
    * `:max_retries` - Maximum retries (default: 3)
    * `:telemetry_prefix` - Telemetry event prefix (default: `[:req_fly]`)

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      req = Req.new() |> ReqFly.attach(
        token: "fly_token",
        base_url: "https://custom.api.dev",
        retry: :transient,
        max_retries: 5
      )

  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, options \\ []) do
    token = options[:token] || get_configured_token()

    if is_nil(token) do
      raise ArgumentError, """
      Fly.io API token is required. Provide it via:
        1. ReqFly.attach(request, token: "your_token")
        2. Application config: config :req_fly, token: "your_token"
      """
    end

    base_url = options[:base_url] || @default_base_url
    retry_strategy = options[:retry] || :safe_transient
    max_retries = options[:max_retries] || 3
    telemetry_prefix = options[:telemetry_prefix] || [:req_fly]

    request
    |> Req.Request.register_options([
      :fly_token,
      :fly_base_url,
      :fly_retry,
      :fly_max_retries,
      :fly_telemetry_prefix
    ])
    |> Req.Request.merge_options(
      fly_token: token,
      fly_base_url: base_url,
      fly_retry: retry_strategy,
      fly_max_retries: max_retries,
      fly_telemetry_prefix: telemetry_prefix,
      decode_json: [keys: :strings]
    )
    |> Req.Request.prepend_request_steps([
      {:fly_base_url, &Steps.attach_base_url/1},
      {:fly_auth, &Steps.attach_auth/1},
      {:fly_headers, &Steps.attach_headers/1}
    ])
    |> Steps.attach_telemetry()
    |> Req.Request.merge_options(
      retry: retry_strategy,
      max_retries: max_retries
    )
  end

  @doc """
  Helper function to make HTTP requests with the configured ReqFly client.

  This is a convenience function that builds the full URL from base_url + path,
  makes the HTTP request, and returns a simplified response tuple.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `method` - HTTP method (`:get`, `:post`, `:put`, `:delete`, etc.)
    * `path` - URL path (will be appended to base_url)
    * `opts` - Additional options (`:params`, `:json`, etc.)

  ## Returns

    * `{:ok, body}` - For successful 2xx responses
    * `{:error, %ReqFly.Error{}}` - For errors

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      ReqFly.request(req, :get, "/apps")
      # => {:ok, [%{"name" => "my-app"}]}

      ReqFly.request(req, :post, "/apps/my-app/machines", json: %{config: %{}})
      # => {:ok, %{"id" => "machine123"}}

      ReqFly.request(req, :get, "/apps/nonexistent")
      # => {:error, %ReqFly.Error{status: 404}}

  """
  @spec request(Req.Request.t(), atom(), String.t(), keyword()) ::
          {:ok, term()} | {:error, ReqFly.Error.t()}
  def request(%Req.Request{} = req, method, path, opts \\ []) do
    request_opts =
      opts
      |> Keyword.put(:url, path)
      |> Keyword.put_new(:params, [])

    case Req.request(req, [{:method, method} | request_opts]) do
      {:ok, %Req.Response{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      {:ok, %Req.Response{} = response} ->
        {:error, ReqFly.Error.from_response(response, method: method, url: path)}

      {:error, exception} ->
        {:error, ReqFly.Error.from_exception(exception)}
    end
  end

  # Private functions

  @spec get_configured_token() :: String.t() | nil
  defp get_configured_token do
    Application.get_env(:req_fly, :token)
  end
end
