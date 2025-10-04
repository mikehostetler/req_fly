defmodule ReqFly.Machines do
  @moduledoc """
  Functions for interacting with Fly.io Machines API.

  The Machines API provides comprehensive operations for managing Fly.io machines
  including lifecycle management (create, start, stop, restart), configuration
  updates, and state monitoring.

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      # List machines in an app
      {:ok, machines} = ReqFly.Machines.list(req, app_name: "my-app")

      # Get machine details
      {:ok, machine} = ReqFly.Machines.get(req, app_name: "my-app", machine_id: "148ed123456789")

      # Create a new machine
      config = %{
        image: "flyio/hellofly:latest",
        guest: %{cpus: 1, memory_mb: 256}
      }
      {:ok, machine} = ReqFly.Machines.create(req, app_name: "my-app", config: config)

      # Start a machine
      {:ok, _} = ReqFly.Machines.start(req, app_name: "my-app", machine_id: "148ed123456789")

      # Stop a machine
      {:ok, _} = ReqFly.Machines.stop(req, app_name: "my-app", machine_id: "148ed123456789")

  """

  @doc """
  Lists all machines in an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)

  ## Returns

    * `{:ok, machines}` - List of machine maps
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, machines} = ReqFly.Machines.list(req, app_name: "my-app")

  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, list(map())} | {:error, ReqFly.Error.t()}
  def list(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    validate_required!(app_name, :app_name)

    ReqFly.request(req, :get, "/apps/#{app_name}/machines")
  end

  @doc """
  Gets details for a specific machine.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)

  ## Returns

    * `{:ok, machine}` - Machine details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, machine} = ReqFly.Machines.get(req,
        app_name: "my-app",
        machine_id: "148ed123456789"
      )

  """
  @spec get(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def get(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)

    ReqFly.request(req, :get, "/apps/#{app_name}/machines/#{machine_id}")
  end

  @doc """
  Creates a new machine in an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:config` - Machine configuration map (required)
      * `:region` - Region to create the machine in (optional)

  ## Returns

    * `{:ok, machine}` - Created machine details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      config = %{
        image: "flyio/hellofly:latest",
        guest: %{cpus: 1, memory_mb: 256}
      }

      {:ok, machine} = ReqFly.Machines.create(req,
        app_name: "my-app",
        config: config
      )

      # With specific region
      {:ok, machine} = ReqFly.Machines.create(req,
        app_name: "my-app",
        config: config,
        region: "sjc"
      )

  """
  @spec create(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def create(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    config = Keyword.get(opts, :config)
    region = Keyword.get(opts, :region)

    validate_required!(app_name, :app_name)
    validate_config!(config)

    json =
      case region do
        nil -> %{config: config}
        region -> %{config: config, region: region}
      end

    ReqFly.request(req, :post, "/apps/#{app_name}/machines", json: json)
  end

  @doc """
  Updates a machine's configuration.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)
      * `:config` - Updated machine configuration map (required)

  ## Returns

    * `{:ok, machine}` - Updated machine details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      config = %{
        image: "flyio/hellofly:latest",
        guest: %{cpus: 2, memory_mb: 512}
      }

      {:ok, machine} = ReqFly.Machines.update(req,
        app_name: "my-app",
        machine_id: "148ed123456789",
        config: config
      )

  """
  @spec update(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def update(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)
    config = Keyword.get(opts, :config)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)
    validate_config!(config)

    ReqFly.request(req, :post, "/apps/#{app_name}/machines/#{machine_id}",
      json: %{config: config}
    )
  end

  @doc """
  Destroys (deletes) a machine.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)

  ## Returns

    * `{:ok, response}` - Deletion confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Machines.destroy(req,
        app_name: "my-app",
        machine_id: "148ed123456789"
      )

  """
  @spec destroy(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def destroy(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)

    ReqFly.request(req, :delete, "/apps/#{app_name}/machines/#{machine_id}")
  end

  @doc """
  Starts a stopped machine.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)

  ## Returns

    * `{:ok, response}` - Start confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Machines.start(req,
        app_name: "my-app",
        machine_id: "148ed123456789"
      )

  """
  @spec start(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def start(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)

    ReqFly.request(req, :post, "/apps/#{app_name}/machines/#{machine_id}/start")
  end

  @doc """
  Stops a running machine.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)

  ## Returns

    * `{:ok, response}` - Stop confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Machines.stop(req,
        app_name: "my-app",
        machine_id: "148ed123456789"
      )

  """
  @spec stop(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def stop(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)

    ReqFly.request(req, :post, "/apps/#{app_name}/machines/#{machine_id}/stop")
  end

  @doc """
  Restarts a machine.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)

  ## Returns

    * `{:ok, response}` - Restart confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Machines.restart(req,
        app_name: "my-app",
        machine_id: "148ed123456789"
      )

  """
  @spec restart(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def restart(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)

    ReqFly.request(req, :post, "/apps/#{app_name}/machines/#{machine_id}/restart")
  end

  @doc """
  Sends a signal to a machine.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)
      * `:signal` - Signal to send (e.g., "SIGTERM", "SIGKILL") (required)

  ## Returns

    * `{:ok, response}` - Signal confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Machines.signal(req,
        app_name: "my-app",
        machine_id: "148ed123456789",
        signal: "SIGTERM"
      )

  """
  @spec signal(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def signal(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)
    signal = Keyword.get(opts, :signal)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)
    validate_required!(signal, :signal)

    ReqFly.request(req, :post, "/apps/#{app_name}/machines/#{machine_id}/signal",
      json: %{signal: signal}
    )
  end

  @doc """
  Waits for a machine to reach a specific state.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:machine_id` - ID of the machine (required)
      * `:instance_id` - Instance ID to wait for (optional)
      * `:state` - State to wait for (e.g., "started", "stopped") (optional)
      * `:timeout` - Timeout in seconds (optional)

  ## Returns

    * `{:ok, response}` - State confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      {:ok, _} = ReqFly.Machines.wait(req,
        app_name: "my-app",
        machine_id: "148ed123456789",
        state: "started",
        timeout: 60
      )

      {:ok, _} = ReqFly.Machines.wait(req,
        app_name: "my-app",
        machine_id: "148ed123456789",
        instance_id: "01H3JK...",
        state: "stopped"
      )

  """
  @spec wait(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def wait(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    machine_id = Keyword.get(opts, :machine_id)

    validate_required!(app_name, :app_name)
    validate_required!(machine_id, :machine_id)

    params =
      [:instance_id, :state, :timeout]
      |> Enum.reduce([], fn key, acc ->
        case Keyword.get(opts, key) do
          nil -> acc
          value -> [{key, value} | acc]
        end
      end)
      |> Enum.reverse()

    ReqFly.request(req, :get, "/apps/#{app_name}/machines/#{machine_id}/wait", params: params)
  end

  # Private helpers

  defp validate_required!(value, _field_name) when is_binary(value) and byte_size(value) > 0 do
    :ok
  end

  defp validate_required!(value, field_name) when is_nil(value) or value == "" do
    raise ArgumentError, "#{field_name} is required"
  end

  defp validate_required!(_value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-empty string"
  end

  defp validate_config!(config) when is_map(config) and map_size(config) > 0 do
    :ok
  end

  defp validate_config!(nil) do
    raise ArgumentError, "config is required"
  end

  defp validate_config!(_) do
    raise ArgumentError, "config must be a non-empty map"
  end
end
