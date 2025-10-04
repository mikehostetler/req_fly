defmodule ReqFly.IntegrationCase do
  @moduledoc """
  Test case template for live Fly.io API integration tests.

  These tests interact with the real Fly.io API and create/destroy actual resources.

  ## Configuration

  Set the `FLY_API_TOKEN` environment variable with a valid Fly.io API token.

  Integration tests are tagged with `:integration` and skipped by default.
  Run them explicitly with:

      mix test --only integration
      mix test test/integration/01_create_app_test.exs

  ## Resource Cleanup

  Each test MUST clean up resources in an `on_exit` callback to avoid costs.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ReqFly.IntegrationCase

      # Tag all tests as integration
      @moduletag :integration
      @moduletag timeout: 120_000

      setup do
        # Ensure we have a valid token
        token = System.get_env("FLY_API_TOKEN")

        if is_nil(token) || token == "" do
          raise """
          FLY_API_TOKEN environment variable is not set.

          Get your token from: https://fly.io/user/personal_access_tokens
          Then set it: export FLY_API_TOKEN=your_token_here
          """
        end

        # Build req client
        req = Req.new() |> ReqFly.attach(token: token)

        {:ok, req: req}
      end
    end
  end

  @doc """
  Generates a unique test resource name with timestamp.

  ## Examples

      iex> test_name("myapp")
      "reqfly-test-myapp-1234567890"
  """
  def test_name(prefix) do
    timestamp = System.system_time(:second)
    "reqfly-test-#{prefix}-#{timestamp}"
  end

  @doc """
  Cleans up an app and all its resources.

  This will attempt to:
  1. List and destroy all machines in the app
  2. Destroy the app itself

  Logs errors but doesn't fail if resources are already gone.
  """
  def cleanup_app(req, app_name) do
    # Try to clean up machines first
    case ReqFly.Machines.list(req, app_name: app_name) do
      {:ok, machines} when is_list(machines) ->
        Enum.each(machines, fn machine ->
          machine_id = machine["id"]

          # Try to stop first (some machines must be stopped before deletion)
          ReqFly.Machines.stop(req, app_name: app_name, machine_id: machine_id)
          Process.sleep(1000)

          # Then destroy
          case ReqFly.Machines.destroy(req, app_name: app_name, machine_id: machine_id) do
            {:ok, _} -> :ok
            # Already gone
            {:error, _} -> :ok
          end
        end)

      _ ->
        :ok
    end

    # Destroy the app
    case ReqFly.Apps.destroy(req, app_name) do
      {:ok, _} -> :ok
      # Already gone
      {:error, _} -> :ok
    end

    # Give Fly.io a moment to process
    Process.sleep(1000)
  end

  @doc """
  Waits for a condition to be true, with timeout.

  ## Examples

      wait_until(fn -> check_something() == :ok end, timeout: 30_000)
  """
  def wait_until(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    interval = Keyword.get(opts, :interval, 1000)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_until(fun, deadline, interval)
  end

  defp do_wait_until(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now >= deadline do
        {:error, :timeout}
      else
        Process.sleep(interval)
        do_wait_until(fun, deadline, interval)
      end
    end
  end
end
