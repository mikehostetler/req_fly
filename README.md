# ReqFly

Req plugin for the Fly.io Machines API.

[![Hex.pm](https://img.shields.io/hexpm/v/req_fly.svg)](https://hex.pm/packages/req_fly)
[![Documentation](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/req_fly)

## Installation

Add `req_fly` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:req_fly, "~> 0.1.0"}
  ]
end
```

## Quick Start

Get your API token from https://fly.io/user/personal_access_tokens, then:

```elixir
# Create a Req client with ReqFly attached
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
    env: %{"PORT" => "8080"},
    guest: %{cpus: 1, memory_mb: 256}
  },
  region: "ewr"
)
```

## Features

- ✅ **Full Fly.io Machines API coverage** - Apps, Machines, Secrets, Volumes, and more
- ✅ **Built-in retries and error handling** - Automatic retry with exponential backoff
- ✅ **Comprehensive documentation** - Every function documented with examples
- ✅ **High-level convenience functions** - Simplified APIs for common workflows
- ✅ **Telemetry support** - Built-in observability for all operations
- ✅ **Well-tested** - 187 tests with real API fixtures using ExVCR

## API Overview

### Low-Level Plugin Usage

ReqFly is a Req plugin that can be used with direct Req calls:

```elixir
req = Req.new() |> ReqFly.attach(token: "your_fly_token")

# Make direct API calls
{:ok, %{body: apps}} = Req.get(req, url: "/apps", params: [org_slug: "personal"])
{:ok, %{body: app}} = Req.post(req, url: "/apps", json: %{app_name: "test", org_slug: "personal"})
{:ok, %{body: machines}} = Req.get(req, url: "/apps/my-app/machines")
```

### High-Level Helper APIs

For convenience, ReqFly provides high-level helper modules:

#### Apps - Create and manage apps

```elixir
ReqFly.Apps.list(req, org_slug: "personal")
ReqFly.Apps.create(req, app_name: "my-app", org_slug: "personal")
ReqFly.Apps.get(req, "my-app")
ReqFly.Apps.destroy(req, "my-app")
```

#### Machines - Full lifecycle management

```elixir
ReqFly.Machines.list(req, app_name: "my-app")
ReqFly.Machines.create(req, app_name: "my-app", config: %{image: "nginx:latest"})
ReqFly.Machines.start(req, app_name: "my-app", machine_id: "148ed...")
ReqFly.Machines.stop(req, app_name: "my-app", machine_id: "148ed...")
ReqFly.Machines.restart(req, app_name: "my-app", machine_id: "148ed...")
ReqFly.Machines.wait(req, app_name: "my-app", machine_id: "148ed...", state: "started")
```

#### Secrets - Manage app secrets

```elixir
ReqFly.Secrets.list(req, app_name: "my-app")
ReqFly.Secrets.create(req, app_name: "my-app", label: "DATABASE_URL", type: "env", value: "postgres://...")
ReqFly.Secrets.generate(req, app_name: "my-app", label: "SECRET_KEY", type: "env")
ReqFly.Secrets.destroy(req, app_name: "my-app", label: "OLD_SECRET")
```

#### Volumes - Persistent storage

```elixir
ReqFly.Volumes.list(req, app_name: "my-app")
ReqFly.Volumes.create(req, app_name: "my-app", name: "data", region: "ewr", size_gb: 10)
ReqFly.Volumes.extend(req, app_name: "my-app", volume_id: "vol_...", size_gb: 20)
ReqFly.Volumes.create_snapshot(req, app_name: "my-app", volume_id: "vol_...")
```

#### Orchestrator - Multi-step workflows

```elixir
# Create app and wait for it to become active
{:ok, app} = ReqFly.Orchestrator.create_app_and_wait(req,
  app_name: "my-app",
  org_slug: "personal",
  timeout: 120
)

# Create machine and wait for it to start
{:ok, machine} = ReqFly.Orchestrator.create_machine_and_wait(req,
  app_name: "my-app",
  config: %{image: "nginx:latest"},
  timeout: 60
)
```

## Configuration

### Explicit Token (Recommended)

```elixir
req = Req.new() |> ReqFly.attach(token: "your_fly_token")
```

### Environment Variable

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))
```

### Application Config

```elixir
# config/config.exs
config :req_fly, token: "your_fly_token"

# In your code
req = Req.new() |> ReqFly.attach()
```

### Runtime Config

```elixir
# config/runtime.exs
config :req_fly, token: System.get_env("FLY_API_TOKEN")
```

### All Options

```elixir
req = Req.new() |> ReqFly.attach(
  token: "your_fly_token",           # API token (required)
  base_url: "https://...",            # Override base URL (optional)
  retry: :safe_transient,             # Retry strategy (default: :safe_transient)
  max_retries: 3,                     # Max retry attempts (default: 3)
  telemetry_prefix: [:req_fly]        # Telemetry event prefix (default: [:req_fly])
)
```

## Usage Examples

### Apps Management

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

# List all apps in your organization
{:ok, apps} = ReqFly.Apps.list(req, org_slug: "personal")
IO.inspect(apps, label: "Apps")

# Create a new app
{:ok, app} = ReqFly.Apps.create(req,
  app_name: "my-new-app",
  org_slug: "personal"
)

# Get app details
{:ok, app} = ReqFly.Apps.get(req, "my-new-app")

# Clean up - destroy app
{:ok, _} = ReqFly.Apps.destroy(req, "my-new-app")
```

### Machine Lifecycle

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

# Create a machine
config = %{
  image: "flyio/hellofly:latest",
  env: %{
    "PORT" => "8080",
    "ENV" => "production"
  },
  guest: %{
    cpus: 1,
    memory_mb: 256
  },
  services: [
    %{
      ports: [
        %{port: 80, handlers: ["http"]},
        %{port: 443, handlers: ["tls", "http"]}
      ],
      protocol: "tcp",
      internal_port: 8080
    }
  ]
}

{:ok, machine} = ReqFly.Machines.create(req,
  app_name: "my-app",
  config: config,
  region: "ewr"
)

machine_id = machine["id"]

# Start the machine
{:ok, _} = ReqFly.Machines.start(req, app_name: "my-app", machine_id: machine_id)

# Wait for it to reach started state
{:ok, ready_machine} = ReqFly.Machines.wait(req,
  app_name: "my-app",
  machine_id: machine_id,
  instance_id: machine["instance_id"],
  state: "started",
  timeout: 60
)

# Stop the machine
{:ok, _} = ReqFly.Machines.stop(req, app_name: "my-app", machine_id: machine_id)

# Destroy the machine
{:ok, _} = ReqFly.Machines.destroy(req, app_name: "my-app", machine_id: machine_id)
```

### Secrets Management

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

# Set a secret
{:ok, _} = ReqFly.Secrets.create(req,
  app_name: "my-app",
  label: "DATABASE_URL",
  type: "env",
  value: "postgres://user:pass@host/db"
)

# Generate a random secret
{:ok, secret} = ReqFly.Secrets.generate(req,
  app_name: "my-app",
  label: "SECRET_KEY_BASE",
  type: "env"
)

IO.puts("Generated secret: #{secret["value"]}")

# List all secrets
{:ok, secrets} = ReqFly.Secrets.list(req, app_name: "my-app")

# Delete a secret
{:ok, _} = ReqFly.Secrets.destroy(req, app_name: "my-app", label: "OLD_SECRET")
```

### Volume Management

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

# Create a volume
{:ok, volume} = ReqFly.Volumes.create(req,
  app_name: "my-app",
  name: "postgres_data",
  region: "ewr",
  size_gb: 10
)

volume_id = volume["id"]

# Extend volume size
{:ok, extended_volume} = ReqFly.Volumes.extend(req,
  app_name: "my-app",
  volume_id: volume_id,
  size_gb: 20
)

# Create a snapshot
{:ok, snapshot} = ReqFly.Volumes.create_snapshot(req,
  app_name: "my-app",
  volume_id: volume_id
)

# List all snapshots
{:ok, snapshots} = ReqFly.Volumes.list_snapshots(req,
  app_name: "my-app",
  volume_id: volume_id
)
```

### Orchestrator Workflows

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

# Create app and wait for it to be ready
{:ok, app} = ReqFly.Orchestrator.create_app_and_wait(req,
  app_name: "production-app",
  org_slug: "personal",
  timeout: 120
)

# Create machine and wait for it to start
config = %{
  image: "nginx:latest",
  guest: %{cpus: 1, memory_mb: 256}
}

{:ok, machine} = ReqFly.Orchestrator.create_machine_and_wait(req,
  app_name: "production-app",
  config: config,
  region: "ewr",
  timeout: 60
)

IO.puts("Machine #{machine["id"]} is ready!")
```

### Error Handling

```elixir
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))

case ReqFly.Apps.get(req, "nonexistent-app") do
  {:ok, app} ->
    IO.puts("Found app: #{app["name"]}")
    
  {:error, %ReqFly.Error{status: 404}} ->
    IO.puts("App not found")
    
  {:error, %ReqFly.Error{status: 401}} ->
    IO.puts("Authentication failed - check your token")
    
  {:error, %ReqFly.Error{status: status, message: message}} ->
    IO.puts("Error #{status}: #{message}")
end
```

### Telemetry

```elixir
# Attach telemetry handler
:telemetry.attach_many(
  "req-fly-handler",
  [
    [:req_fly, :request, :start],
    [:req_fly, :request, :stop],
    [:req_fly, :request, :exception]
  ],
  fn event_name, measurements, metadata, _config ->
    IO.inspect({event_name, measurements, metadata})
  end,
  nil
)

# Make requests and observe telemetry events
req = Req.new() |> ReqFly.attach(token: System.get_env("FLY_API_TOKEN"))
ReqFly.Apps.list(req, org_slug: "personal")
```

## Resources

- **[Full API Documentation](https://hexdocs.pm/req_fly)** - Complete module and function documentation
- **[Fly.io Machines API Documentation](https://fly.io/docs/machines/api/)** - Official Fly.io API docs
- **[Req Documentation](https://hexdocs.pm/req)** - Learn about the Req HTTP client

### Module Documentation

- [ReqFly](https://hexdocs.pm/req_fly/ReqFly.html) - Main plugin module
- [ReqFly.Apps](https://hexdocs.pm/req_fly/ReqFly.Apps.html) - Apps API
- [ReqFly.Machines](https://hexdocs.pm/req_fly/ReqFly.Machines.html) - Machines API
- [ReqFly.Secrets](https://hexdocs.pm/req_fly/ReqFly.Secrets.html) - Secrets API
- [ReqFly.Volumes](https://hexdocs.pm/req_fly/ReqFly.Volumes.html) - Volumes API
- [ReqFly.Orchestrator](https://hexdocs.pm/req_fly/ReqFly.Orchestrator.html) - Multi-step workflows

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run with ExVCR cassettes
FLY_API_TOKEN=your_token mix test
```

### Building Documentation

```bash
# Generate documentation
mix docs

# Open documentation in browser
open doc/index.html
```

### Code Quality

```bash
# Run static analysis
mix credo

# Run type checking
mix dialyzer

# Format code
mix format
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Acknowledgments

Built with [Req](https://github.com/wojtekmach/req) - the awesome Elixir HTTP client.
