defmodule ReqFlyTest do
  use ExUnit.Case, async: true
  doctest ReqFly

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "attach/2" do
    test "sets up request with token from options" do
      req = Req.new() |> ReqFly.attach(token: "test_token")

      assert req.options.fly_token == "test_token"
      assert req.options.fly_base_url == "https://api.machines.dev/v1"
      assert req.options.fly_retry == :safe_transient
      assert req.options.fly_max_retries == 3
      assert req.options.fly_telemetry_prefix == [:req_fly]
    end

    test "uses token from application config when not provided" do
      Application.put_env(:req_fly, :token, "config_token")
      on_exit(fn -> Application.delete_env(:req_fly, :token) end)

      req = Req.new() |> ReqFly.attach()

      assert req.options.fly_token == "config_token"
    end

    test "raises when token is missing" do
      Application.delete_env(:req_fly, :token)

      assert_raise ArgumentError, ~r/Fly.io API token is required/, fn ->
        Req.new() |> ReqFly.attach()
      end
    end

    test "accepts custom base_url" do
      req = Req.new() |> ReqFly.attach(token: "test", base_url: "https://custom.api")

      assert req.options.fly_base_url == "https://custom.api"
    end

    test "accepts custom retry configuration" do
      req = Req.new() |> ReqFly.attach(token: "test", retry: :transient, max_retries: 5)

      assert req.options.fly_retry == :transient
      assert req.options.fly_max_retries == 5
      assert req.options.retry == :transient
      assert req.options.max_retries == 5
    end

    test "accepts custom telemetry prefix" do
      req = Req.new() |> ReqFly.attach(token: "test", telemetry_prefix: [:my_app, :fly])

      assert req.options.fly_telemetry_prefix == [:my_app, :fly]
    end

    test "registers custom options" do
      req = Req.new() |> ReqFly.attach(token: "test")

      assert :fly_token in req.registered_options
      assert :fly_base_url in req.registered_options
      assert :fly_retry in req.registered_options
      assert :fly_max_retries in req.registered_options
      assert :fly_telemetry_prefix in req.registered_options
    end
  end

  describe "authentication" do
    test "injects Authorization header", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        assert auth_header == ["Bearer test_token"]
        Plug.Conn.resp(conn, 200, Jason.encode!([]))
      end)

      req =
        Req.new(base_url: "http://localhost:#{bypass.port}")
        |> ReqFly.attach(token: "test_token", base_url: "http://localhost:#{bypass.port}")

      assert {:ok, _response} = Req.get(req, url: "/apps")
    end
  end

  describe "headers" do
    test "adds User-Agent and Accept headers", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        user_agent = Plug.Conn.get_req_header(conn, "user-agent")
        accept = Plug.Conn.get_req_header(conn, "accept")

        assert user_agent == ["req_fly/0.1.0 (+Req)"]
        assert accept == ["application/json"]

        Plug.Conn.resp(conn, 200, Jason.encode!([]))
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      assert {:ok, _response} = Req.get(req, url: "/apps")
    end
  end

  describe "error handling" do
    test "converts 404 response to ReqFly.Error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps/nonexistent", fn conn ->
        body = Jason.encode!(%{"error" => "not_found", "message" => "App not found"})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, body)
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      {:error, error} = ReqFly.request(req, :get, "/apps/nonexistent")

      assert %ReqFly.Error{} = error
      assert error.status == 404
      assert error.code == "not_found"
      assert error.reason == "App not found"
    end

    test "extracts fly-request-id from response headers", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/error", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("fly-request-id", "abc123xyz")
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "internal_error"}))
      end)

      req =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}",
          max_retries: 0
        )

      {:error, error} = ReqFly.request(req, :get, "/error")

      assert error.request_id == "abc123xyz"
    end

    test "handles connection errors", %{bypass: bypass} do
      Bypass.down(bypass)

      req =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}",
          max_retries: 1,
          retry_delay: fn _ -> 1 end
        )

      {:error, error} = ReqFly.request(req, :get, "/apps")

      assert %ReqFly.Error{} = error
      assert error.reason != nil
    end
  end

  describe "retry behavior" do
    test "retries on 503 for safe methods (GET)", %{bypass: bypass} do
      pid = self()
      ref = make_ref()
      agent = start_supervised!({Agent, fn -> 0 end})

      Bypass.expect(bypass, "GET", "/apps", fn conn ->
        count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)
        send(pid, {ref, :request, count})

        case count do
          0 ->
            Plug.Conn.resp(conn, 503, Jason.encode!(%{"error" => "service_unavailable"}))

          _ ->
            Plug.Conn.resp(conn, 200, Jason.encode!([]))
        end
      end)

      req =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}",
          retry: :safe_transient,
          max_retries: 2,
          retry_delay: fn _ -> 10 end
        )

      assert {:ok, %Req.Response{status: 200}} = Req.get(req, url: "/apps")

      assert_received {^ref, :request, 0}
      assert_received {^ref, :request, 1}
    end

    test "does not retry POST by default on 503", %{bypass: bypass} do
      pid = self()
      ref = make_ref()

      Bypass.expect(bypass, "POST", "/apps", fn conn ->
        send(pid, {ref, :request})
        Plug.Conn.resp(conn, 503, Jason.encode!(%{"error" => "service_unavailable"}))
      end)

      req =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}",
          retry: :safe_transient,
          max_retries: 2,
          retry_delay: fn _ -> 10 end
        )

      task =
        Task.async(fn ->
          Req.post(req, url: "/apps", json: %{name: "test"})
        end)

      assert_receive {^ref, :request}

      refute_receive {^ref, :request}, 200

      assert {:ok, %Req.Response{status: 503}} = Task.await(task)
    end
  end

  describe "telemetry" do
    test "emits start and stop events", %{bypass: bypass} do
      :telemetry.attach_many(
        "test-telemetry",
        [
          [:req_fly, :request, :start],
          [:req_fly, :request, :stop]
        ],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {:telemetry, event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      on_exit(fn -> :telemetry.detach("test-telemetry") end)

      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!([]))
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      Req.get!(req, url: "/apps")

      assert_receive {:telemetry, [:req_fly, :request, :start], %{system_time: _}, metadata}
      assert metadata.method == :get
      assert is_binary(metadata.url)

      assert_receive {:telemetry, [:req_fly, :request, :stop], %{duration: duration}, metadata}
      assert is_integer(duration)
      assert metadata.status == 200
    end

    test "emits exception event on error", %{bypass: bypass} do
      :telemetry.attach(
        "test-telemetry-error",
        [:req_fly, :request, :exception],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {:telemetry, event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      on_exit(fn -> :telemetry.detach("test-telemetry-error") end)

      Bypass.down(bypass)

      req =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}",
          max_retries: 1,
          retry_delay: fn _ -> 1 end
        )

      catch_error(Req.get!(req, url: "/apps"))

      assert_receive {:telemetry, [:req_fly, :request, :exception], %{duration: _}, metadata}
      assert is_binary(metadata.error)
    end

    test "uses custom telemetry prefix", %{bypass: bypass} do
      :telemetry.attach(
        "test-custom-prefix",
        [:my_app, :fly, :request, :start],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {:telemetry, event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      on_exit(fn -> :telemetry.detach("test-custom-prefix") end)

      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!([]))
      end)

      req =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}",
          telemetry_prefix: [:my_app, :fly]
        )

      Req.get!(req, url: "/apps")

      assert_receive {:telemetry, [:my_app, :fly, :request, :start], _, _}
    end
  end

  describe "request/4 helper" do
    test "returns {:ok, body} for successful requests", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{"name" => "my-app"}]))
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      assert {:ok, [%{"name" => "my-app"}]} = ReqFly.request(req, :get, "/apps")
    end

    test "returns {:error, ReqFly.Error} for error responses", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps/nonexistent", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(%{"error" => "not_found"}))
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      assert {:error, %ReqFly.Error{status: 404}} =
               ReqFly.request(req, :get, "/apps/nonexistent")
    end

    test "supports POST with JSON body", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/apps/my-app/machines", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"config" => %{"image" => "nginx"}}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(201, Jason.encode!(%{"id" => "machine123"}))
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      assert {:ok, %{"id" => "machine123"}} =
               ReqFly.request(req, :post, "/apps/my-app/machines",
                 json: %{config: %{image: "nginx"}}
               )
    end

    test "supports query parameters", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        assert conn.query_string == "region=iad"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!([]))
      end)

      req =
        Req.new()
        |> ReqFly.attach(token: "test", base_url: "http://localhost:#{bypass.port}")

      assert {:ok, []} = ReqFly.request(req, :get, "/apps", params: [region: "iad"])
    end
  end
end
