defmodule ReqFly.Orchestrator do
  @moduledoc """
  Multi-step workflow orchestration for complex Fly.io operations.

  This module provides high-level orchestration functions that combine multiple
  API calls with polling and waiting logic to simplify complex workflows like
  creating and waiting for apps or machines to reach desired states.

  ## Polling and Backoff Strategy

  All orchestration functions use exponential backoff with jitter:

  - Initial delay: 500ms
  - Backoff multiplier: 1.5x
  - Maximum delay: 5000ms
  - Jitter: 0-20% random variance

  ## Telemetry

  All orchestration functions emit telemetry events:

  - `[:req_fly, :orchestrator, :wait, :start]` - When waiting begins
  - `[:req_fly, :orchestrator, :wait, :stop]` - When waiting completes successfully
  - `[:req_fly, :orchestrator, :wait, :timeout]` - When waiting times out

  Metadata includes:

  - `operation` - The operation being performed (e.g., "create_app_and_wait")
  - `duration` - Time elapsed in milliseconds (for stop/timeout events)
  - `attempts` - Number of polling attempts made
  - `reason` - Error reason (for timeout events)

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      # Create app and wait for it to become active
      {:ok, app} = ReqFly.Orchestrator.create_app_and_wait(req,
        app_name: "my-app",
        org_slug: "my-org",
        timeout: 120
      )

      # Create machine and wait for it to start
      config = %{
        image: "flyio/hellofly:latest",
        guest: %{cpus: 1, memory_mb: 256}
      }
      
      {:ok, machine} = ReqFly.Orchestrator.create_machine_and_wait(req,
        app_name: "my-app",
        config: config,
        state: "started",
        timeout: 90
      )

  """

  alias ReqFly.{Apps, Error, Machines}

  @initial_delay 500
  @max_delay 5000
  @backoff_multiplier 1.5
  @jitter_range 0.2
  @default_timeout 60

  @doc """
  Creates a Fly.io app and waits for it to become active.

  This orchestration function combines app creation with polling to ensure
  the app is fully provisioned before returning.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app to create (required)
      * `:org_slug` - Organization slug (required)
      * `:timeout` - Maximum time to wait in seconds (default: 60)

  ## Returns

    * `{:ok, app}` - App details when active
    * `{:error, %ReqFly.Error{}}` - Error details (creation failure or timeout)

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      
      {:ok, app} = ReqFly.Orchestrator.create_app_and_wait(req,
        app_name: "my-app",
        org_slug: "my-org"
      )

      # With custom timeout
      {:ok, app} = ReqFly.Orchestrator.create_app_and_wait(req,
        app_name: "my-app",
        org_slug: "my-org",
        timeout: 120
      )

  """
  @spec create_app_and_wait(Req.Request.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_app_and_wait(req, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    app_name = Keyword.get(opts, :app_name)

    with {:ok, _app} <- Apps.create(req, opts) do
      check_fn = fn ->
        case Apps.get(req, app_name) do
          {:ok, %{"status" => "active"} = app} ->
            {:ok, app}

          {:ok, _app} ->
            {:continue, "waiting for app to become active"}

          {:error, error} ->
            {:error, error}
        end
      end

      poll_until(req, check_fn,
        timeout: timeout,
        operation: "create_app_and_wait",
        error_message: "Timeout waiting for app to become active"
      )
    end
  end

  @doc """
  Creates a machine and waits for it to reach the desired state.

  This orchestration function creates a machine and then waits for it to
  reach the specified state. It first attempts to use the wait endpoint
  (if an instance_id is available), then falls back to polling if needed.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:config` - Machine configuration map (required)
      * `:region` - Region to create the machine in (optional)
      * `:state` - Desired state to wait for (default: "started")
      * `:timeout` - Maximum time to wait in seconds (default: 60)

  ## Returns

    * `{:ok, machine}` - Machine details when desired state is reached
    * `{:error, %ReqFly.Error{}}` - Error details (creation failure or timeout)

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      config = %{
        image: "flyio/hellofly:latest",
        guest: %{cpus: 1, memory_mb: 256}
      }

      # Create and wait for machine to start
      {:ok, machine} = ReqFly.Orchestrator.create_machine_and_wait(req,
        app_name: "my-app",
        config: config
      )

      # Create and wait for specific state
      {:ok, machine} = ReqFly.Orchestrator.create_machine_and_wait(req,
        app_name: "my-app",
        config: config,
        state: "stopped",
        timeout: 90
      )

  """
  @spec create_machine_and_wait(Req.Request.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_machine_and_wait(req, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    desired_state = Keyword.get(opts, :state, "started")
    app_name = Keyword.get(opts, :app_name)

    with {:ok, machine} <- Machines.create(req, opts) do
      machine_id = machine["id"]
      instance_id = machine["instance_id"]

      if instance_id do
        case try_wait_endpoint(req, app_name, machine_id, instance_id, desired_state, timeout) do
          {:ok, result} ->
            {:ok, result}

          {:error, _wait_error} ->
            poll_machine_state(req, app_name, machine_id, desired_state, timeout)
        end
      else
        poll_machine_state(req, app_name, machine_id, desired_state, timeout)
      end
    end
  end

  @doc """
  Generic polling function with exponential backoff.

  Repeatedly calls a check function until it returns success, error, or timeout.
  Uses exponential backoff with jitter between attempts.

  ## Parameters

    * `req` - A Req.Request (used for telemetry context)
    * `check_fn` - Function that returns:
      * `{:ok, result}` - Success, stop polling
      * `{:continue, reason}` - Keep polling
      * `{:error, error}` - Error, stop polling
    * `opts` - Options keyword list
      * `:timeout` - Maximum time to wait in seconds (required)
      * `:operation` - Operation name for telemetry (optional)
      * `:error_message` - Custom timeout error message (optional)

  ## Returns

    * `{:ok, result}` - When check_fn returns success
    * `{:error, %ReqFly.Error{}}` - On timeout or when check_fn returns error

  ## Examples

      check_fn = fn ->
        case MyAPI.get_status() do
          {:ok, %{ready: true}} -> {:ok, :ready}
          {:ok, _} -> {:continue, "not ready"}
          error -> {:error, error}
        end
      end

      {:ok, :ready} = ReqFly.Orchestrator.poll_until(req, check_fn,
        timeout: 30,
        operation: "wait_for_ready"
      )

  """
  @spec poll_until(
          Req.Request.t(),
          (-> {:ok, term()} | {:continue, term()} | {:error, term()}),
          keyword()
        ) :: {:ok, term()} | {:error, Error.t()}
  def poll_until(_req, check_fn, opts) do
    timeout_ms = Keyword.fetch!(opts, :timeout) * 1000
    operation = Keyword.get(opts, :operation, "poll_until")
    error_message = Keyword.get(opts, :error_message, "Timeout waiting for condition")
    initial_delay = Keyword.get(opts, :initial_delay, @initial_delay)

    start_time = System.monotonic_time(:millisecond)

    emit_telemetry(:start, %{}, %{operation: operation})

    result = do_poll(check_fn, start_time, timeout_ms, initial_delay, 0)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, value} ->
        emit_telemetry(:stop, %{duration: duration}, %{
          operation: operation,
          attempts: get_attempts(result)
        })

        {:ok, value}

      {:error, {:timeout, attempts}} ->
        emit_telemetry(:timeout, %{duration: duration}, %{
          operation: operation,
          attempts: attempts,
          reason: error_message
        })

        {:error, %Error{reason: error_message}}

      {:error, error} ->
        {:error, error}
    end
  end

  # Private functions

  defp try_wait_endpoint(req, app_name, machine_id, instance_id, state, timeout) do
    Machines.wait(req,
      app_name: app_name,
      machine_id: machine_id,
      instance_id: instance_id,
      state: state,
      timeout: timeout
    )
  end

  defp poll_machine_state(req, app_name, machine_id, desired_state, timeout) do
    check_fn = fn ->
      case Machines.get(req, app_name: app_name, machine_id: machine_id) do
        {:ok, %{"state" => ^desired_state} = machine} ->
          {:ok, machine}

        {:ok, _machine} ->
          {:continue, "waiting for machine to reach state: #{desired_state}"}

        {:error, error} ->
          {:error, error}
      end
    end

    poll_until(req, check_fn,
      timeout: timeout,
      operation: "create_machine_and_wait",
      error_message: "Timeout waiting for machine to reach state: #{desired_state}"
    )
  end

  defp do_poll(check_fn, start_time, timeout_ms, delay, attempts) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout_ms do
      {:error, {:timeout, attempts}}
    else
      case check_fn.() do
        {:ok, result} ->
          {:ok, result}

        {:continue, _reason} ->
          remaining = timeout_ms - elapsed
          actual_delay = min(delay, remaining)

          if actual_delay > 0 do
            Process.sleep(actual_delay)
          end

          next_delay = calculate_next_delay(delay)
          do_poll(check_fn, start_time, timeout_ms, next_delay, attempts + 1)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp calculate_next_delay(current_delay) do
    base_next = min(trunc(current_delay * @backoff_multiplier), @max_delay)
    jitter = trunc(base_next * @jitter_range * :rand.uniform())
    base_next + jitter
  end

  defp get_attempts(_), do: 0

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:req_fly, :orchestrator, :wait, event],
      measurements,
      metadata
    )
  end
end
