defmodule ReqFly.MachinesTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    token = "test_token"

    req =
      Req.new(base_url: "http://localhost:#{bypass.port}")
      |> ReqFly.attach(
        token: token,
        base_url: "http://localhost:#{bypass.port}/v1",
        retry_delay: fn _ -> 1 end
      )

    {:ok, bypass: bypass, req: req}
  end

  defp json_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, body)
  end

  describe "list/2" do
    test "lists machines successfully", %{bypass: bypass, req: req} do
      machines = [
        %{"id" => "machine-1", "state" => "started"},
        %{"id" => "machine-2", "state" => "stopped"}
      ]

      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/machines", fn conn ->
        json_response(conn, 200, Jason.encode!(machines))
      end)

      assert {:ok, ^machines} = ReqFly.Machines.list(req, app_name: "my-app")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.list(req, [])
      end
    end

    test "raises when app_name is empty", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.list(req, app_name: "")
      end
    end
  end

  describe "get/2" do
    test "gets a machine successfully", %{bypass: bypass, req: req} do
      machine = %{"id" => "machine-123", "state" => "started"}

      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/machines/machine-123", fn conn ->
        json_response(conn, 200, Jason.encode!(machine))
      end)

      assert {:ok, ^machine} =
               ReqFly.Machines.get(req, app_name: "my-app", machine_id: "machine-123")
    end

    test "handles 404 when machine not found", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/machines/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "Machine not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "Machine not found"}} =
               ReqFly.Machines.get(req, app_name: "my-app", machine_id: "nonexistent")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.get(req, machine_id: "machine-123")
      end
    end

    test "raises when machine_id is missing", %{req: req} do
      assert_raise ArgumentError, "machine_id is required", fn ->
        ReqFly.Machines.get(req, app_name: "my-app")
      end
    end
  end

  describe "create/2" do
    test "creates a machine successfully", %{bypass: bypass, req: req} do
      config = %{image: "flyio/hellofly:latest", guest: %{cpus: 1, memory_mb: 256}}
      machine = %{"id" => "machine-123", "state" => "created"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/machines", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["config"] == %{
                 "image" => "flyio/hellofly:latest",
                 "guest" => %{"cpus" => 1, "memory_mb" => 256}
               }

        assert Map.has_key?(payload, "region") == false

        json_response(conn, 201, Jason.encode!(machine))
      end)

      assert {:ok, ^machine} = ReqFly.Machines.create(req, app_name: "my-app", config: config)
    end

    test "creates a machine with region", %{bypass: bypass, req: req} do
      config = %{image: "flyio/hellofly:latest"}
      machine = %{"id" => "machine-123", "region" => "sjc"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/machines", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["region"] == "sjc"
        assert payload["config"]["image"] == "flyio/hellofly:latest"

        json_response(conn, 201, Jason.encode!(machine))
      end)

      assert {:ok, ^machine} =
               ReqFly.Machines.create(req, app_name: "my-app", config: config, region: "sjc")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.create(req, config: %{})
      end
    end

    test "raises when config is missing", %{req: req} do
      assert_raise ArgumentError, "config is required", fn ->
        ReqFly.Machines.create(req, app_name: "my-app")
      end
    end

    test "raises when config is empty map", %{req: req} do
      assert_raise ArgumentError, "config must be a non-empty map", fn ->
        ReqFly.Machines.create(req, app_name: "my-app", config: %{})
      end
    end

    test "raises when config is not a map", %{req: req} do
      assert_raise ArgumentError, "config must be a non-empty map", fn ->
        ReqFly.Machines.create(req, app_name: "my-app", config: "invalid")
      end
    end
  end

  describe "update/2" do
    test "updates a machine successfully", %{bypass: bypass, req: req} do
      config = %{guest: %{cpus: 2, memory_mb: 512}}
      machine = %{"id" => "machine-123", "state" => "started"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/machines/machine-123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["config"]["guest"] == %{"cpus" => 2, "memory_mb" => 512}

        json_response(conn, 200, Jason.encode!(machine))
      end)

      assert {:ok, ^machine} =
               ReqFly.Machines.update(req,
                 app_name: "my-app",
                 machine_id: "machine-123",
                 config: config
               )
    end

    test "raises when config is missing", %{req: req} do
      assert_raise ArgumentError, "config is required", fn ->
        ReqFly.Machines.update(req, app_name: "my-app", machine_id: "machine-123")
      end
    end
  end

  describe "destroy/2" do
    test "destroys a machine successfully", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "DELETE", "/v1/apps/my-app/machines/machine-123", fn conn ->
        json_response(conn, 200, Jason.encode!(%{"ok" => true}))
      end)

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.destroy(req, app_name: "my-app", machine_id: "machine-123")
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "DELETE", "/v1/apps/my-app/machines/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "Machine not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404}} =
               ReqFly.Machines.destroy(req, app_name: "my-app", machine_id: "nonexistent")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.destroy(req, machine_id: "machine-123")
      end
    end

    test "raises when machine_id is missing", %{req: req} do
      assert_raise ArgumentError, "machine_id is required", fn ->
        ReqFly.Machines.destroy(req, app_name: "my-app")
      end
    end
  end

  describe "start/2" do
    test "starts a machine successfully", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/machines/machine-123/start", fn conn ->
        json_response(conn, 200, Jason.encode!(%{"ok" => true}))
      end)

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.start(req, app_name: "my-app", machine_id: "machine-123")
    end

    test "raises when required params are missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.start(req, machine_id: "machine-123")
      end
    end
  end

  describe "stop/2" do
    test "stops a machine successfully", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/machines/machine-123/stop", fn conn ->
        json_response(conn, 200, Jason.encode!(%{"ok" => true}))
      end)

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.stop(req, app_name: "my-app", machine_id: "machine-123")
    end

    test "raises when required params are missing", %{req: req} do
      assert_raise ArgumentError, "machine_id is required", fn ->
        ReqFly.Machines.stop(req, app_name: "my-app")
      end
    end
  end

  describe "restart/2" do
    test "restarts a machine successfully", %{bypass: bypass, req: req} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/apps/my-app/machines/machine-123/restart",
        fn conn ->
          json_response(conn, 200, Jason.encode!(%{"ok" => true}))
        end
      )

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.restart(req, app_name: "my-app", machine_id: "machine-123")
    end

    test "handles 500 error", %{bypass: bypass, req: req} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/apps/my-app/machines/machine-123/restart",
        fn conn ->
          error = %{"error" => "internal_error", "message" => "Server error"}
          json_response(conn, 500, Jason.encode!(error))
        end
      )

      assert {:error, %ReqFly.Error{status: 500, reason: "Server error"}} =
               ReqFly.Machines.restart(req, app_name: "my-app", machine_id: "machine-123")
    end
  end

  describe "signal/2" do
    test "sends signal to machine successfully", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/machines/machine-123/signal", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["signal"] == "SIGTERM"

        json_response(conn, 200, Jason.encode!(%{"ok" => true}))
      end)

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.signal(req,
                 app_name: "my-app",
                 machine_id: "machine-123",
                 signal: "SIGTERM"
               )
    end

    test "raises when signal is missing", %{req: req} do
      assert_raise ArgumentError, "signal is required", fn ->
        ReqFly.Machines.signal(req, app_name: "my-app", machine_id: "machine-123")
      end
    end
  end

  describe "wait/2" do
    test "waits for machine state with all params", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/machines/machine-123/wait", fn conn ->
        query = URI.decode_query(conn.query_string)

        assert query["instance_id"] == "01H3JK"
        assert query["state"] == "started"
        assert query["timeout"] == "60"

        json_response(conn, 200, Jason.encode!(%{"ok" => true, "state" => "started"}))
      end)

      assert {:ok, %{"ok" => true, "state" => "started"}} =
               ReqFly.Machines.wait(req,
                 app_name: "my-app",
                 machine_id: "machine-123",
                 instance_id: "01H3JK",
                 state: "started",
                 timeout: 60
               )
    end

    test "waits for machine with minimal params", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/machines/machine-123/wait", fn conn ->
        assert conn.query_string == ""

        json_response(conn, 200, Jason.encode!(%{"ok" => true}))
      end)

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.wait(req, app_name: "my-app", machine_id: "machine-123")
    end

    test "waits with only state param", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/machines/machine-123/wait", fn conn ->
        query = URI.decode_query(conn.query_string)

        assert query["state"] == "stopped"
        assert Map.has_key?(query, "instance_id") == false
        assert Map.has_key?(query, "timeout") == false

        json_response(conn, 200, Jason.encode!(%{"ok" => true}))
      end)

      assert {:ok, %{"ok" => true}} =
               ReqFly.Machines.wait(req,
                 app_name: "my-app",
                 machine_id: "machine-123",
                 state: "stopped"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Machines.wait(req, machine_id: "machine-123")
      end
    end

    test "raises when machine_id is missing", %{req: req} do
      assert_raise ArgumentError, "machine_id is required", fn ->
        ReqFly.Machines.wait(req, app_name: "my-app")
      end
    end
  end
end
