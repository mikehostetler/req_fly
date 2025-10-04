# ReqFly - Implementation Specification

**Package Name:** `req_fly`  
**Version:** 0.1.0  
**Target Elixir:** ~> 1.14  
**Primary Dependency:** `req` ~> 0.5  
**License:** MIT  
**Repository:** New standalone package

---

## 1. Project Overview

### Purpose
A modern Elixir client for the Fly.io Machines API implemented as a Req plugin, providing both low-level HTTP access and high-level convenience functions.

### Design Philosophy
- **Req-first:** Built natively as a Req plugin, not a wrapper
- **Composable:** Works seamlessly with other Req plugins
- **Flexible:** Support both direct Req calls and high-level helpers
- **Well-typed:** Comprehensive typespecs and structs
- **Documented:** Extensive docs with examples
- **Tested:** High test coverage with real API fixtures

### Key Differentiators
- Idiomatic Req plugin architecture
- Built-in retry logic and telemetry
- Optional high-level API for common workflows
- Structured error handling
- No runtime configuration requirements (library-friendly)

---

## 2. Architecture

### Core Plugin Structure

```
req_fly/
├── lib/
│   ├── req_fly.ex                    # Main plugin with attach/1,2
│   ├── req_fly/
│   │   ├── apps.ex                   # High-level Apps API
│   │   ├── machines.ex               # High-level Machines API
│   │   ├── secrets.ex                # High-level Secrets API
│   │   ├── volumes.ex                # High-level Volumes API
│   │   ├── orchestrator.ex           # Multi-step workflows
│   │   ├── error.ex                  # Error struct and handling
│   │   └── steps.ex                  # Custom Req steps
│   └── mix/
│       └── tasks/
│           └── req_fly.gen.ex        # Code generation from OpenAPI spec
├── test/
│   ├── req_fly_test.exs
│   ├── req_fly/
│   │   ├── apps_test.exs
│   │   ├── machines_test.exs
│   │   ├── secrets_test.exs
│   │   ├── volumes_test.exs
│   │   └── orchestrator_test.exs
│   ├── support/
│   │   └── fly_case.ex               # Shared test helpers
│   └── fixtures/                     # ExVCR cassettes
├── priv/
│   └── openapi.json                  # Fly.io OpenAPI spec
├── mix.exs
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .formatter.exs
```

---

## 3. API Design

### 3.1 Low-Level Plugin API

```elixir
# Basic usage - attach plugin to Req
req = Req.new() |> ReqFly.attach(token: "fly_token_here")

# Make direct API calls
Req.get!(req, url: "/apps")
Req.post!(req, url: "/apps", json: %{app_name: "test", org_slug: "personal"})
Req.get!(req, url: "/apps/my-app/machines")

# Plugin options
req = Req.new() |> ReqFly.attach(
  token: "...",                    # API token (required)
  base_url: "https://...",         # Override base URL (optional)
  retry: :safe_transient,          # Retry strategy (default)
  max_retries: 3,                  # Max retry attempts
  telemetry_prefix: [:req_fly]     # Telemetry event prefix
)
```

### 3.2 High-Level Helper API

```elixir
# Apps
ReqFly.Apps.list(req, org_slug: "personal")
ReqFly.Apps.create(req, app_name: "my-app", org_slug: "personal")
ReqFly.Apps.get(req, "my-app")
ReqFly.Apps.destroy(req, "my-app")

# Machines
ReqFly.Machines.list(req, app_name: "my-app")
ReqFly.Machines.get(req, app_name: "my-app", machine_id: "...")
ReqFly.Machines.create(req, app_name: "my-app", config: %{
  image: "nginx:latest",
  region: "ewr",
  env: %{"FOO" => "bar"}
})
ReqFly.Machines.update(req, app_name: "my-app", machine_id: "...", config: %{...})
ReqFly.Machines.destroy(req, app_name: "my-app", machine_id: "...")
ReqFly.Machines.start(req, app_name: "my-app", machine_id: "...")
ReqFly.Machines.stop(req, app_name: "my-app", machine_id: "...")
ReqFly.Machines.restart(req, app_name: "my-app", machine_id: "...")
ReqFly.Machines.signal(req, app_name: "my-app", machine_id: "...", signal: "SIGTERM")
ReqFly.Machines.wait(req, app_name: "my-app", machine_id: "...", 
  instance_id: "...", state: "started", timeout: 60)

# Secrets
ReqFly.Secrets.list(req, app_name: "my-app")
ReqFly.Secrets.create(req, app_name: "my-app", label: "MY_SECRET", 
  type: "env", value: "secret_value")
ReqFly.Secrets.generate(req, app_name: "my-app", label: "TOKEN", type: "env")
ReqFly.Secrets.destroy(req, app_name: "my-app", label: "MY_SECRET")

# Volumes
ReqFly.Volumes.list(req, app_name: "my-app")
ReqFly.Volumes.create(req, app_name: "my-app", name: "data", region: "ewr", size_gb: 10)
ReqFly.Volumes.get(req, app_name: "my-app", volume_id: "...")
ReqFly.Volumes.update(req, app_name: "my-app", volume_id: "...", params: %{...})
ReqFly.Volumes.delete(req, app_name: "my-app", volume_id: "...")
ReqFly.Volumes.extend(req, app_name: "my-app", volume_id: "...", size_gb: 20)

# Volume Snapshots
ReqFly.Volumes.list_snapshots(req, app_name: "my-app", volume_id: "...")
ReqFly.Volumes.create_snapshot(req, app_name: "my-app", volume_id: "...")

# Orchestrator - Multi-step workflows
ReqFly.Orchestrator.create_app_and_wait(req, 
  app_name: "my-app", 
  org_slug: "personal",
  timeout: 60
)
ReqFly.Orchestrator.create_machine_and_wait(req,
  app_name: "my-app",
  config: %{...},
  timeout: 60
)
```

### 3.3 Configuration Patterns

```elixir
# 1. Explicit token (recommended for libraries)
req = Req.new() |> ReqFly.attach(token: token)

# 2. Environment variable
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

# 3. Application config (optional convenience)
# config/config.exs
config :req_fly, token: "fly_token_here"

# lib/my_app.ex
req = Req.new() |> ReqFly.attach()  # Reads from config if available

# 4. Runtime config
# config/runtime.exs
config :req_fly, token: System.get_env("FLY_API_TOKEN")
```

---

## 4. Implementation Details

### 4.1 Main Plugin Module (`lib/req_fly.ex`)

```elixir
defmodule ReqFly do
  @moduledoc """
  Req plugin for the Fly.io Machines API.
  
  ## Usage
  
      req = Req.new() |> ReqFly.attach(token: "your_fly_token")
      
      # Low-level API
      Req.get!(req, url: "/apps")
      
      # High-level API
      ReqFly.Apps.list(req, org_slug: "personal")
  
  ## Options
  
    * `:token` - Fly.io API token (required unless configured)
    * `:base_url` - API base URL (default: "https://api.machines.dev/v1")
    * `:retry` - Retry strategy (default: :safe_transient)
    * `:max_retries` - Maximum retry attempts (default: 3)
    * `:telemetry_prefix` - Telemetry event prefix (default: [:req_fly])
  
  ## Authentication
  
  Get your API token from: https://fly.io/user/personal_access_tokens
  
  ## Examples
  
      # Create a request client
      req = Req.new() |> ReqFly.attach(token: "...")
      
      # List apps
      {:ok, %{body: apps}} = Req.get(req, url: "/apps", params: [org_slug: "personal"])
      
      # Create app (high-level)
      {:ok, app} = ReqFly.Apps.create(req, app_name: "my-app", org_slug: "personal")
  """
  
  @type options :: [
    token: String.t(),
    base_url: String.t(),
    retry: atom(),
    max_retries: pos_integer(),
    telemetry_prefix: [atom()]
  ]
  
  @default_base_url "https://api.machines.dev/v1"
  @default_retry :safe_transient
  @default_max_retries 3
  
  @doc """
  Attaches the ReqFly plugin to a Req request.
  """
  @spec attach(Req.Request.t(), options()) :: Req.Request.t()
  def attach(%Req.Request{} = request, options \\ []) do
    request
    |> Req.Request.register_options([
      :fly_token,
      :fly_base_url, 
      :fly_retry,
      :fly_max_retries,
      :fly_telemetry_prefix
    ])
    |> Req.Request.merge_options(
      fly_token: options[:token] || get_configured_token(),
      fly_base_url: options[:base_url] || @default_base_url,
      fly_retry: options[:retry] || @default_retry,
      fly_max_retries: options[:max_retries] || @default_max_retries,
      fly_telemetry_prefix: options[:telemetry_prefix] || [:req_fly],
      base_url: options[:base_url] || @default_base_url,
      retry: options[:retry] || @default_retry,
      max_retries: options[:max_retries] || @default_max_retries
    )
    |> Req.Request.prepend_request_steps(fly_auth: &ReqFly.Steps.add_auth/1)
    |> Req.Request.append_response_steps(fly_handle_response: &ReqFly.Steps.handle_response/1)
    |> Req.Request.append_error_steps(fly_handle_error: &ReqFly.Steps.handle_error/1)
  end
  
  defp get_configured_token do
    Application.get_env(:req_fly, :token)
  end
end
```

### 4.2 Custom Steps Module (`lib/req_fly/steps.ex`)

```elixir
defmodule ReqFly.Steps do
  @moduledoc false
  
  require Logger
  
  def add_auth(request) do
    token = request.options[:fly_token]
    
    if is_nil(token) do
      raise ArgumentError, """
      Fly.io API token is required. Provide it via:
      
        Req.new() |> ReqFly.attach(token: "your_token")
      
      Or configure it:
      
        config :req_fly, token: "your_token"
      
      Get your token at: https://fly.io/user/personal_access_tokens
      """
    end
    
    Req.Request.put_header(request, "authorization", "Bearer #{token}")
  end
  
  def handle_response({request, response}) do
    case response.status do
      status when status in 200..299 ->
        {request, response}
      
      status when status >= 400 ->
        error = build_error(response)
        {request, ReqFly.Error.exception(error)}
      
      _ ->
        {request, response}
    end
  end
  
  def handle_error({request, exception}) do
    Logger.warning("Fly.io API request failed", 
      error: Exception.message(exception),
      request_url: request.url
    )
    {request, exception}
  end
  
  defp build_error(response) do
    %{
      status: response.status,
      message: extract_message(response.body),
      body: response.body,
      headers: response.headers
    }
  end
  
  defp extract_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: "Fly.io API error"
end
```

### 4.3 Error Module (`lib/req_fly/error.ex`)

```elixir
defmodule ReqFly.Error do
  @moduledoc """
  Exception struct for Fly.io API errors.
  """
  
  defexception [:status, :message, :body, :headers]
  
  @type t :: %__MODULE__{
    status: integer(),
    message: String.t(),
    body: map() | String.t(),
    headers: list()
  }
  
  def exception(attrs) do
    struct!(__MODULE__, attrs)
  end
  
  def message(%__MODULE__{status: status, message: msg}) do
    "Fly.io API error (#{status}): #{msg}"
  end
end
```

### 4.4 High-Level Apps Module (`lib/req_fly/apps.ex`)

```elixir
defmodule ReqFly.Apps do
  @moduledoc """
  High-level API for Fly.io Apps.
  """
  
  @doc """
  Lists all apps for an organization.
  
  ## Options
  
    * `:org_slug` - Organization slug (default: "personal")
  
  ## Examples
  
      {:ok, apps} = ReqFly.Apps.list(req, org_slug: "personal")
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, list(map())} | {:error, Exception.t()}
  def list(req, opts \\ []) do
    org_slug = Keyword.get(opts, :org_slug, "personal")
    
    case Req.get(req, url: "/apps", params: [org_slug: org_slug]) do
      {:ok, %{body: apps}} -> {:ok, apps}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Creates a new app.
  
  ## Options
  
    * `:app_name` - Name of the app (required)
    * `:org_slug` - Organization slug (required)
    * `:network` - Network name (optional)
    * `:enable_subdomains` - Enable subdomains (optional, default: false)
  
  ## Examples
  
      {:ok, app} = ReqFly.Apps.create(req, 
        app_name: "my-app",
        org_slug: "personal"
      )
  """
  @spec create(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def create(req, opts) do
    params = %{
      app_name: Keyword.fetch!(opts, :app_name),
      org_slug: Keyword.fetch!(opts, :org_slug),
      network: Keyword.get(opts, :network, ""),
      enable_subdomains: Keyword.get(opts, :enable_subdomains, false)
    }
    
    case Req.post(req, url: "/apps", json: params) do
      {:ok, %{body: app}} -> {:ok, app}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Gets details for a specific app.
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Exception.t()}
  def get(req, app_name) do
    case Req.get(req, url: "/apps/#{app_name}") do
      {:ok, %{body: app}} -> {:ok, app}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Destroys an app.
  """
  @spec destroy(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, Exception.t()}
  def destroy(req, app_name) do
    case Req.delete(req, url: "/apps/#{app_name}") do
      {:ok, %{body: result}} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end
end
```

### 4.5 High-Level Machines Module (`lib/req_fly/machines.ex`)

```elixir
defmodule ReqFly.Machines do
  @moduledoc """
  High-level API for Fly.io Machines.
  """
  
  @doc """
  Lists all machines for an app.
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, list(map())} | {:error, Exception.t()}
  def list(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    
    case Req.get(req, url: "/apps/#{app_name}/machines") do
      {:ok, %{body: machines}} -> {:ok, machines}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Gets a specific machine.
  """
  @spec get(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def get(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    
    case Req.get(req, url: "/apps/#{app_name}/machines/#{machine_id}") do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Creates a new machine.
  
  ## Options
  
    * `:app_name` - App name (required)
    * `:config` - Machine config map (required)
    * `:name` - Machine name (optional)
    * `:region` - Region (optional)
  
  ## Examples
  
      {:ok, machine} = ReqFly.Machines.create(req,
        app_name: "my-app",
        config: %{
          image: "nginx:latest",
          env: %{"PORT" => "8080"}
        },
        region: "ewr"
      )
  """
  @spec create(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def create(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    config = Keyword.fetch!(opts, :config)
    
    params = 
      %{config: config}
      |> maybe_put(:name, opts[:name])
      |> maybe_put(:region, opts[:region])
    
    case Req.post(req, url: "/apps/#{app_name}/machines", json: params) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Updates a machine.
  """
  @spec update(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def update(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    
    params = 
      %{}
      |> maybe_put(:config, opts[:config])
      |> maybe_put(:name, opts[:name])
      |> maybe_put(:region, opts[:region])
    
    case Req.patch(req, url: "/apps/#{app_name}/machines/#{machine_id}", json: params) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Destroys a machine.
  """
  @spec destroy(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def destroy(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    
    case Req.delete(req, url: "/apps/#{app_name}/machines/#{machine_id}") do
      {:ok, %{body: result}} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Starts a machine.
  """
  @spec start(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def start(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    
    case Req.post(req, url: "/apps/#{app_name}/machines/#{machine_id}/start", json: %{}) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Stops a machine.
  """
  @spec stop(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def stop(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    
    case Req.post(req, url: "/apps/#{app_name}/machines/#{machine_id}/stop", json: %{}) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Restarts a machine.
  """
  @spec restart(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def restart(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    
    case Req.post(req, url: "/apps/#{app_name}/machines/#{machine_id}/restart", json: %{}) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Sends a signal to a machine.
  """
  @spec signal(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def signal(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    signal = Keyword.fetch!(opts, :signal)
    
    case Req.post(req, url: "/apps/#{app_name}/machines/#{machine_id}/signal", 
                  json: %{signal: signal}) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Waits for a machine to reach a specific state.
  """
  @spec wait(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def wait(req, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    machine_id = Keyword.fetch!(opts, :machine_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    state = Keyword.get(opts, :state, "started")
    timeout = Keyword.get(opts, :timeout, 60)
    
    params = [
      instance_id: instance_id,
      state: state,
      timeout: timeout
    ]
    
    case Req.get(req, url: "/apps/#{app_name}/machines/#{machine_id}/wait", params: params) do
      {:ok, %{body: machine}} -> {:ok, machine}
      {:error, error} -> {:error, error}
    end
  end
  
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
```

### 4.6 Orchestrator Module (`lib/req_fly/orchestrator.ex`)

```elixir
defmodule ReqFly.Orchestrator do
  @moduledoc """
  Higher-level orchestration for multi-step Fly.io operations.
  """
  
  alias ReqFly.{Apps, Machines}
  
  @doc """
  Creates an app and waits for it to become active.
  
  ## Options
  
    * `:app_name` - App name (required)
    * `:org_slug` - Organization slug (required)
    * `:timeout` - Timeout in seconds (default: 60)
    * `:interval` - Poll interval in ms (default: 2000)
  """
  @spec create_app_and_wait(Req.Request.t(), keyword()) :: 
    {:ok, map()} | {:error, Exception.t()}
  def create_app_and_wait(req, opts) do
    timeout = Keyword.get(opts, :timeout, 60)
    interval = Keyword.get(opts, :interval, 2000)
    
    with {:ok, app} <- Apps.create(req, opts),
         {:ok, active_app} <- wait_for_app_active(req, app["name"], timeout, interval) do
      {:ok, active_app}
    end
  end
  
  @doc """
  Creates a machine and waits for it to reach started state.
  
  ## Options
  
    * `:app_name` - App name (required)
    * `:config` - Machine config (required)
    * `:timeout` - Timeout in seconds (default: 60)
    * Plus any other machine creation options
  """
  @spec create_machine_and_wait(Req.Request.t(), keyword()) :: 
    {:ok, map()} | {:error, Exception.t()}
  def create_machine_and_wait(req, opts) do
    timeout = Keyword.get(opts, :timeout, 60)
    app_name = Keyword.fetch!(opts, :app_name)
    
    with {:ok, machine} <- Machines.create(req, opts),
         {:ok, ready_machine} <- Machines.wait(req,
           app_name: app_name,
           machine_id: machine["id"],
           instance_id: machine["instance_id"],
           state: "started",
           timeout: timeout
         ) do
      {:ok, ready_machine}
    end
  end
  
  defp wait_for_app_active(req, app_name, timeout, interval) do
    deadline = System.monotonic_time(:second) + timeout
    poll_app_status(req, app_name, deadline, interval)
  end
  
  defp poll_app_status(req, app_name, deadline, interval) do
    case Apps.get(req, app_name) do
      {:ok, %{"status" => status} = app} when status != "pending" ->
        {:ok, app}
      
      {:ok, _pending} ->
        if System.monotonic_time(:second) >= deadline do
          {:error, %ReqFly.Error{
            status: 408,
            message: "Timeout waiting for app to become active",
            body: %{app_name: app_name},
            headers: []
          }}
        else
          Process.sleep(interval)
          poll_app_status(req, app_name, deadline, interval)
        end
      
      {:error, error} ->
        {:error, error}
    end
  end
end
```

### 4.7 Mix Project (`mix.exs`)

```elixir
defmodule ReqFly.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/YOUR_USERNAME/req_fly"

  def project do
    [
      app: :req_fly,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Hex
      description: "Req plugin for the Fly.io Machines API",
      package: package(),
      
      # Docs
      name: "ReqFly",
      docs: docs(),
      
      # Testing
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        "test.watch": :test,
        vcr: :test,
        "vcr.delete": :test,
        "vcr.check": :test,
        "vcr.show": :test
      ],
      
      # Coverage
      test_coverage: [tool: ExCoveralls],
      
      # Dialyzer
      dialyzer: [
        plt_add_apps: [:ex_unit],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Required
      {:req, "~> 0.5"},
      
      # Optional - for code generation
      {:jason, "~> 1.4"},
      
      # Development & Testing
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:exvcr, "~> 0.15", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "req_fly",
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Fly.io Docs" => "https://fly.io/docs/machines/api/",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "ReqFly",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "High-level API": [
          ReqFly.Apps,
          ReqFly.Machines,
          ReqFly.Secrets,
          ReqFly.Volumes,
          ReqFly.Orchestrator
        ],
        "Internal": [
          ReqFly.Steps,
          ReqFly.Error
        ]
      ]
    ]
  end
end
```

---

## 5. Testing Strategy

### 5.1 Test Infrastructure

```elixir
# test/support/fly_case.ex
defmodule ReqFly.FlyCase do
  use ExUnit.CaseTemplate
  
  using do
    quote do
      use ExUnit.Case
      use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
      
      import ReqFly.FlyCase
      
      @moduletag :capture_log
    end
  end
  
  def build_req(opts \\ []) do
    token = opts[:token] || System.get_env("FLY_API_TOKEN") || "test_token"
    
    Req.new()
    |> ReqFly.attach(Keyword.put(opts, :token, token))
  end
end
```

### 5.2 Test Examples

```elixir
# test/req_fly/apps_test.exs
defmodule ReqFly.AppsTest do
  use ReqFly.FlyCase
  
  describe "list/2" do
    test "lists apps for personal organization" do
      use_cassette "apps/list_personal" do
        req = build_req()
        
        assert {:ok, apps} = ReqFly.Apps.list(req, org_slug: "personal")
        assert is_list(apps)
      end
    end
  end
  
  describe "create/2" do
    test "creates a new app" do
      use_cassette "apps/create" do
        req = build_req()
        
        assert {:ok, app} = ReqFly.Apps.create(req,
          app_name: "test-app",
          org_slug: "personal"
        )
        
        assert app["name"] == "test-app"
        assert app["status"] in ["pending", "active"]
      end
    end
    
    test "returns error for invalid params" do
      use_cassette "apps/create_invalid" do
        req = build_req()
        
        assert {:error, %ReqFly.Error{status: 400}} = 
          ReqFly.Apps.create(req, app_name: "", org_slug: "")
      end
    end
  end
end
```

### 5.3 Coverage Goals

- **Line coverage:** 90%+
- **All public functions tested**
- **Error scenarios covered**
- **Integration tests with VCR cassettes**

---

## 6. Documentation Requirements

### 6.1 README.md Structure

```markdown
# ReqFly

Req plugin for the Fly.io Machines API.

## Installation

```elixir
def deps do
  [
    {:req_fly, "~> 0.1"}
  ]
end
```

## Quick Start

```elixir
# Get your token from: https://fly.io/user/personal_access_tokens
req = Req.new() |> ReqFly.attach(token: "your_fly_token")

# List apps
{:ok, apps} = ReqFly.Apps.list(req, org_slug: "personal")

# Create an app
{:ok, app} = ReqFly.Apps.create(req, 
  app_name: "my-app",
  org_slug: "personal"
)

# Create a machine
{:ok, machine} = ReqFly.Machines.create(req,
  app_name: "my-app",
  config: %{
    image: "nginx:latest",
    env: %{"PORT" => "8080"}
  },
  region: "ewr"
)
```

## Features

- ✅ Full Fly.io Machines API coverage
- ✅ Built-in retries and error handling
- ✅ Comprehensive documentation
- ✅ High-level convenience functions
- ✅ Telemetry support
- ✅ Well-tested with VCR fixtures

## Resources

- Apps - Create and manage Fly.io apps
- Machines - Full machine lifecycle management
- Secrets - Manage app secrets
- Volumes - Persistent storage
- Orchestrator - Multi-step workflows

## Configuration

[... configuration examples ...]

## Examples

[... comprehensive examples ...]

## License

MIT
```

### 6.2 Module Documentation

Every public module and function must have:
- Clear `@moduledoc`
- Function `@doc` with examples
- `@spec` type specifications
- Parameter descriptions
- Return value descriptions

---

## 7. Migration from fly_machine_client

### Code to Port

1. **Parameter validation logic** from `helpers.ex`
2. **Test fixtures** from ExVCR cassettes
3. **API endpoint knowledge** from all resource modules
4. **Orchestration patterns** from `orchestrator.ex`
5. **OpenAPI spec** `spec.json`

### NOT to Port

- Tesla-specific middleware
- Client instantiation patterns
- Old error handling approach

---

## 8. Publishing Checklist

### Pre-publish

- [ ] All modules documented
- [ ] README complete with examples
- [ ] CHANGELOG.md created
- [ ] LICENSE file (MIT)
- [ ] All tests passing
- [ ] Dialyzer clean
- [ ] Credo passing (strict mode)
- [ ] ExDoc generates successfully
- [ ] Version set to 0.1.0

### Hex Package

- [ ] Package metadata in mix.exs
- [ ] GitHub repository created
- [ ] CI/CD setup (GitHub Actions)
- [ ] mix hex.build validates
- [ ] mix hex.publish --dry-run succeeds

### Post-publish

- [ ] Publish to Hex: `mix hex.publish`
- [ ] Tag release on GitHub: `git tag v0.1.0`
- [ ] Publish docs: Automatic via Hex
- [ ] Announce on Elixir Forum
- [ ] Add to Req plugins list (if available)

---

## 9. Future Enhancements

### v0.2.0
- [ ] Complete OpenAPI spec coverage
- [ ] Response structs (typed responses)
- [ ] Stream support for logs/events
- [ ] Rate limiting middleware

### v0.3.0
- [ ] GraphQL API support
- [ ] Code generation from OpenAPI spec
- [ ] Enhanced telemetry with metrics
- [ ] Circuit breaker pattern

### v1.0.0
- [ ] Stable API
- [ ] Production battle-tested
- [ ] Full test coverage
- [ ] Performance benchmarks

---

## 10. Implementation Timeline

### Phase 1: Core Plugin (2-3 days)
- Day 1: Project setup, core plugin, steps, error handling
- Day 2: Apps + Machines high-level APIs
- Day 3: Secrets + Volumes + Orchestrator

### Phase 2: Testing (1-2 days)
- Day 4: Port tests from fly_machine_client
- Day 5: Additional test coverage, edge cases

### Phase 3: Documentation (1 day)
- Day 6: Complete README, module docs, examples

### Phase 4: Publishing (0.5 days)
- Day 7: CI/CD, final checks, Hex publish

**Total:** 4-7 days for full implementation

---

## 11. Success Criteria

A successful v0.1.0 release means:

1. ✅ All core Fly.io resources supported (Apps, Machines, Secrets, Volumes)
2. ✅ 90%+ test coverage
3. ✅ Clean dialyzer run
4. ✅ Comprehensive documentation
5. ✅ Published to Hex
6. ✅ Works as drop-in Req plugin
7. ✅ Better DX than fly_machine_client

---

## References

- Fly.io Machines API: https://fly.io/docs/machines/api/
- OpenAPI Spec: https://api.machines.dev/swagger/doc.json
- Req Documentation: https://hexdocs.pm/req
- Req Plugin Guide: https://hexdocs.pm/req/Req.Request.html#module-writing-plugins
- Original Implementation: fly_machine_client codebase
