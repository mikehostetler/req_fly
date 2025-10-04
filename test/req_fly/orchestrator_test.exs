defmodule ReqFly.OrchestratorTest do
  use ExUnit.Case, async: true
  import ReqFly.FlyCase

  alias ReqFly.Orchestrator

  defp capture_orchestrator_events(fun) do
    parent = self()
    ref = make_ref()

    handler_id = {:orchestrator_test_handler, ref}

    :telemetry.attach_many(
      handler_id,
      [
        [:req_fly, :orchestrator, :wait, :start],
        [:req_fly, :orchestrator, :wait, :stop],
        [:req_fly, :orchestrator, :wait, :timeout]
      ],
      fn event_name, measurements, metadata, _config ->
        send(parent, {ref, event_name, measurements, metadata})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    collect_events(ref, [])
  end

  defp collect_events(ref, acc) do
    receive do
      {^ref, event_name, measurements, metadata} ->
        collect_events(ref, [{event_name, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp json_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, body)
  end

  setup do
    bypass = Bypass.open()

    req =
      Req.new(base_url: "http://localhost:#{bypass.port}")
      |> ReqFly.attach(
        token: "test_token",
        base_url: "http://localhost:#{bypass.port}/v1",
        retry_delay: fn _ -> 1 end
      )

    {:ok, bypass: bypass, req: req}
  end

  describe "create_app_and_wait/2" do
    test "succeeds when app is immediately active", %{bypass: bypass, req: req} do
      app_response = %{
        "id" => "app-123",
        "name" => "test-app",
        "status" => "active",
        "organization" => %{"slug" => "test-org"}
      }

      Bypass.expect_once(bypass, "POST", "/v1/apps", fn conn ->
        json_response(conn, 200, Jason.encode!(app_response))
      end)

      Bypass.expect_once(bypass, "GET", "/v1/apps/test-app", fn conn ->
        json_response(conn, 200, Jason.encode!(app_response))
      end)

      assert {:ok, app} =
               Orchestrator.create_app_and_wait(req,
                 app_name: "test-app",
                 org_slug: "test-org",
                 initial_delay: 1
               )

      assert app["status"] == "active"
      assert app["name"] == "test-app"
    end

    test "succeeds when app becomes active after polling", %{bypass: bypass, req: req} do
      create_response = %{
        "id" => "app-123",
        "name" => "test-app",
        "status" => "pending",
        "organization" => %{"slug" => "test-org"}
      }

      active_response = %{create_response | "status" => "active"}

      Bypass.expect_once(bypass, "POST", "/v1/apps", fn conn ->
        json_response(conn, 200, Jason.encode!(create_response))
      end)

      call_count = :counters.new(1, [])

      Bypass.expect(bypass, "GET", "/v1/apps/test-app", fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        response =
          if count < 2 do
            create_response
          else
            active_response
          end

        json_response(conn, 200, Jason.encode!(response))
      end)

      assert {:ok, app} =
               Orchestrator.create_app_and_wait(req,
                 app_name: "test-app",
                 org_slug: "test-org",
                 timeout: 5,
                 initial_delay: 1
               )

      assert app["status"] == "active"
      assert :counters.get(call_count, 1) >= 2
    end

    test "times out when app never becomes active", %{bypass: bypass, req: req} do
      pending_response = %{
        "id" => "app-123",
        "name" => "test-app",
        "status" => "pending",
        "organization" => %{"slug" => "test-org"}
      }

      Bypass.expect(bypass, "POST", "/v1/apps", fn conn ->
        json_response(conn, 200, Jason.encode!(pending_response))
      end)

      Bypass.expect(bypass, "GET", "/v1/apps/test-app", fn conn ->
        json_response(conn, 200, Jason.encode!(pending_response))
      end)

      assert {:error, error} =
               Orchestrator.create_app_and_wait(req,
                 app_name: "test-app",
                 org_slug: "test-org",
                 timeout: 1,
                 initial_delay: 1
               )

      assert error.reason == "Timeout waiting for app to become active"
    end

    test "returns error when app creation fails", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/v1/apps", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          422,
          Jason.encode!(%{"error" => "invalid_name", "message" => "App name is invalid"})
        )
      end)

      assert {:error, error} =
               Orchestrator.create_app_and_wait(req,
                 app_name: "invalid name",
                 org_slug: "test-org",
                 initial_delay: 1
               )

      assert error.status == 422
      assert error.code == "invalid_name"
    end

    test "validates required parameters" do
      req = Req.new() |> ReqFly.attach(token: "test")

      assert_raise ArgumentError, "app_name is required", fn ->
        Orchestrator.create_app_and_wait(req, org_slug: "test-org")
      end

      assert_raise ArgumentError, "org_slug is required", fn ->
        Orchestrator.create_app_and_wait(req, app_name: "test-app")
      end
    end

    test "emits telemetry events", %{bypass: bypass, req: req} do
      app_response = %{
        "id" => "app-123",
        "name" => "test-app",
        "status" => "active",
        "organization" => %{"slug" => "test-org"}
      }

      Bypass.stub(bypass, "POST", "/v1/apps", fn conn ->
        json_response(conn, 200, Jason.encode!(app_response))
      end)

      Bypass.stub(bypass, "GET", "/v1/apps/test-app", fn conn ->
        json_response(conn, 200, Jason.encode!(app_response))
      end)

      events =
        capture_orchestrator_events(fn ->
          Orchestrator.create_app_and_wait(req,
            app_name: "test-app",
            org_slug: "test-org",
            initial_delay: 1
          )
        end)

      assert_telemetry_event(events, [:req_fly, :orchestrator, :wait, :start], %{
        operation: "create_app_and_wait"
      })

      assert_telemetry_event(events, [:req_fly, :orchestrator, :wait, :stop], %{
        operation: "create_app_and_wait"
      })
    end
  end

  describe "create_machine_and_wait/2" do
    test "succeeds using wait endpoint when instance_id is available", %{bypass: bypass, req: req} do
      machine_response = %{
        "id" => "machine-123",
        "instance_id" => "instance-456",
        "state" => "started",
        "config" => %{"image" => "flyio/test:latest"}
      }

      wait_response = %{"ok" => true}

      Bypass.expect_once(bypass, "POST", "/v1/apps/test-app/machines", fn conn ->
        json_response(conn, 200, Jason.encode!(machine_response))
      end)

      Bypass.expect_once(bypass, "GET", "/v1/apps/test-app/machines/machine-123/wait", fn conn ->
        params = URI.decode_query(conn.query_string)
        assert params["instance_id"] == "instance-456"
        assert params["state"] == "started"
        json_response(conn, 200, Jason.encode!(wait_response))
      end)

      assert {:ok, result} =
               Orchestrator.create_machine_and_wait(req,
                 app_name: "test-app",
                 config: %{image: "flyio/test:latest"},
                 initial_delay: 1
               )

      assert result == wait_response
    end

    test "falls back to polling when wait endpoint fails", %{bypass: bypass, req: req} do
      machine_response = %{
        "id" => "machine-123",
        "instance_id" => "instance-456",
        "state" => "creating",
        "config" => %{"image" => "flyio/test:latest"}
      }

      started_response = %{machine_response | "state" => "started"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/test-app/machines", fn conn ->
        json_response(conn, 200, Jason.encode!(machine_response))
      end)

      Bypass.expect(bypass, "GET", "/v1/apps/test-app/machines/machine-123/wait", fn conn ->
        json_response(conn, 500, Jason.encode!(%{"error" => "wait_unavailable"}))
      end)

      call_count = :counters.new(1, [])

      Bypass.expect(bypass, "GET", "/v1/apps/test-app/machines/machine-123", fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        response = if count < 2, do: machine_response, else: started_response
        json_response(conn, 200, Jason.encode!(response))
      end)

      assert {:ok, machine} =
               Orchestrator.create_machine_and_wait(req,
                 app_name: "test-app",
                 config: %{image: "flyio/test:latest"},
                 timeout: 5,
                 initial_delay: 1
               )

      assert machine["state"] == "started"
      assert :counters.get(call_count, 1) >= 2
    end

    test "succeeds when machine reaches started state after polling", %{bypass: bypass, req: req} do
      machine_response = %{
        "id" => "machine-123",
        "state" => "creating",
        "config" => %{"image" => "flyio/test:latest"}
      }

      started_response = %{machine_response | "state" => "started"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/test-app/machines", fn conn ->
        json_response(conn, 200, Jason.encode!(machine_response))
      end)

      call_count = :counters.new(1, [])

      Bypass.expect(bypass, "GET", "/v1/apps/test-app/machines/machine-123", fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        response = if count < 3, do: machine_response, else: started_response
        json_response(conn, 200, Jason.encode!(response))
      end)

      assert {:ok, machine} =
               Orchestrator.create_machine_and_wait(req,
                 app_name: "test-app",
                 config: %{image: "flyio/test:latest"},
                 timeout: 5,
                 initial_delay: 1
               )

      assert machine["state"] == "started"
      assert :counters.get(call_count, 1) >= 3
    end

    test "times out when machine never reaches desired state", %{bypass: bypass, req: req} do
      machine_response = %{
        "id" => "machine-123",
        "state" => "creating",
        "config" => %{"image" => "flyio/test:latest"}
      }

      Bypass.expect(bypass, "POST", "/v1/apps/test-app/machines", fn conn ->
        json_response(conn, 200, Jason.encode!(machine_response))
      end)

      Bypass.expect(bypass, "GET", "/v1/apps/test-app/machines/machine-123", fn conn ->
        json_response(conn, 200, Jason.encode!(machine_response))
      end)

      assert {:error, error} =
               Orchestrator.create_machine_and_wait(req,
                 app_name: "test-app",
                 config: %{image: "flyio/test:latest"},
                 timeout: 1,
                 initial_delay: 1
               )

      assert error.reason == "Timeout waiting for machine to reach state: started"
    end

    test "returns error when machine creation fails", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/v1/apps/test-app/machines", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          422,
          Jason.encode!(%{"error" => "invalid_config", "message" => "Invalid configuration"})
        )
      end)

      assert {:error, error} =
               Orchestrator.create_machine_and_wait(req,
                 app_name: "test-app",
                 config: %{image: "flyio/test:latest"},
                 initial_delay: 1
               )

      assert error.status == 422
      assert error.code == "invalid_config"
    end

    test "validates required parameters" do
      req = Req.new() |> ReqFly.attach(token: "test")

      assert_raise ArgumentError, "app_name is required", fn ->
        Orchestrator.create_machine_and_wait(req, config: %{image: "test"})
      end

      assert_raise ArgumentError, "config is required", fn ->
        Orchestrator.create_machine_and_wait(req, app_name: "test-app")
      end
    end

    test "supports custom state option", %{bypass: bypass, req: req} do
      machine_response = %{
        "id" => "machine-123",
        "state" => "started",
        "config" => %{"image" => "flyio/test:latest"}
      }

      stopped_response = %{machine_response | "state" => "stopped"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/test-app/machines", fn conn ->
        json_response(conn, 200, Jason.encode!(machine_response))
      end)

      call_count = :counters.new(1, [])

      Bypass.expect(bypass, "GET", "/v1/apps/test-app/machines/machine-123", fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        response = if count < 2, do: machine_response, else: stopped_response
        json_response(conn, 200, Jason.encode!(response))
      end)

      assert {:ok, machine} =
               Orchestrator.create_machine_and_wait(req,
                 app_name: "test-app",
                 config: %{image: "flyio/test:latest"},
                 state: "stopped",
                 timeout: 5,
                 initial_delay: 1
               )

      assert machine["state"] == "stopped"
    end
  end

  describe "poll_until/3" do
    test "succeeds on first check" do
      req = Req.new() |> ReqFly.attach(token: "test")

      check_fn = fn -> {:ok, :success} end

      assert {:ok, :success} =
               Orchestrator.poll_until(req, check_fn,
                 timeout: 5,
                 operation: "test_poll",
                 initial_delay: 1
               )
    end

    test "succeeds after retries" do
      req = Req.new() |> ReqFly.attach(token: "test")
      call_count = :counters.new(1, [])

      check_fn = fn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 3 do
          {:continue, "not ready"}
        else
          {:ok, :ready}
        end
      end

      assert {:ok, :ready} =
               Orchestrator.poll_until(req, check_fn,
                 timeout: 5,
                 operation: "test_poll",
                 initial_delay: 1
               )

      assert :counters.get(call_count, 1) >= 3
    end

    test "times out after max duration" do
      req = Req.new() |> ReqFly.attach(token: "test")

      check_fn = fn -> {:continue, "never ready"} end

      assert {:error, error} =
               Orchestrator.poll_until(req, check_fn,
                 timeout: 1,
                 operation: "test_poll",
                 error_message: "Custom timeout message",
                 initial_delay: 1
               )

      assert error.reason == "Custom timeout message"
    end

    test "uses default error message when not specified" do
      req = Req.new() |> ReqFly.attach(token: "test")

      check_fn = fn -> {:continue, "never ready"} end

      assert {:error, error} =
               Orchestrator.poll_until(req, check_fn,
                 timeout: 1,
                 operation: "test_poll",
                 initial_delay: 1
               )

      assert error.reason == "Timeout waiting for condition"
    end

    test "returns error from check function" do
      req = Req.new() |> ReqFly.attach(token: "test")
      error = %ReqFly.Error{reason: "check failed", status: 500}

      check_fn = fn -> {:error, error} end

      assert {:error, ^error} =
               Orchestrator.poll_until(req, check_fn,
                 timeout: 5,
                 operation: "test_poll",
                 initial_delay: 1
               )
    end

    test "implements exponential backoff" do
      req = Req.new() |> ReqFly.attach(token: "test")
      call_count = :counters.new(1, [])
      timestamps = Agent.start_link(fn -> [] end)
      {:ok, agent} = timestamps

      check_fn = fn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)
        Agent.update(agent, fn list -> [System.monotonic_time(:millisecond) | list] end)

        if count < 4 do
          {:continue, "not ready"}
        else
          {:ok, :ready}
        end
      end

      start_time = System.monotonic_time(:millisecond)

      assert {:ok, :ready} =
               Orchestrator.poll_until(req, check_fn,
                 timeout: 10,
                 operation: "test_poll"
               )

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert duration >= 500
      assert :counters.get(call_count, 1) >= 4

      Agent.stop(agent)
    end

    test "emits telemetry events for success" do
      req = Req.new() |> ReqFly.attach(token: "test")
      check_fn = fn -> {:ok, :success} end

      events =
        capture_orchestrator_events(fn ->
          Orchestrator.poll_until(req, check_fn,
            timeout: 5,
            operation: "telemetry_test",
            initial_delay: 1
          )
        end)

      assert_telemetry_event(events, [:req_fly, :orchestrator, :wait, :start], %{
        operation: "telemetry_test"
      })

      assert_telemetry_event(events, [:req_fly, :orchestrator, :wait, :stop], %{
        operation: "telemetry_test"
      })

      stop_events =
        Enum.filter(events, fn {name, _, _} ->
          name == [:req_fly, :orchestrator, :wait, :stop]
        end)

      assert length(stop_events) > 0
      {_, measurements, _} = hd(stop_events)
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
    end

    test "emits telemetry events for timeout" do
      req = Req.new() |> ReqFly.attach(token: "test")
      check_fn = fn -> {:continue, "never ready"} end

      events =
        capture_orchestrator_events(fn ->
          Orchestrator.poll_until(req, check_fn,
            timeout: 1,
            operation: "timeout_test",
            error_message: "Test timeout",
            initial_delay: 1
          )
        end)

      assert_telemetry_event(events, [:req_fly, :orchestrator, :wait, :start], %{
        operation: "timeout_test"
      })

      assert_telemetry_event(events, [:req_fly, :orchestrator, :wait, :timeout], %{
        operation: "timeout_test",
        reason: "Test timeout"
      })

      timeout_events =
        Enum.filter(events, fn {name, _, _} ->
          name == [:req_fly, :orchestrator, :wait, :timeout]
        end)

      assert length(timeout_events) > 0
      {_, measurements, metadata} = hd(timeout_events)
      assert is_integer(measurements.duration)
      assert measurements.duration >= 1000
      assert is_integer(metadata.attempts)
      assert metadata.attempts > 0
    end
  end
end
