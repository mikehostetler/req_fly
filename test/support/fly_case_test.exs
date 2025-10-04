defmodule ReqFly.FlyCaseTest do
  @moduledoc """
  Integration tests demonstrating how to use ReqFly.FlyCase.

  These tests show:
  - How to use build_req/1
  - How to use ExVCR cassettes
  - How to capture and assert telemetry events
  - How Authorization headers are filtered
  """

  use ReqFly.FlyCase
  use ExUnit.Case, async: false

  describe "build_req/1" do
    test "builds a configured Req client" do
      req = build_req()

      assert %Req.Request{} = req
      assert req.options[:fly_token] in ["dummy_token_for_tests", System.get_env("FLY_API_TOKEN")]
      assert req.options[:fly_base_url] == "https://api.machines.dev/v1"
    end

    test "accepts custom token" do
      req = build_req(token: "custom_token_123")

      assert req.options[:fly_token] == "custom_token_123"
    end

    test "accepts custom base_url" do
      req = build_req(base_url: "https://custom.api.dev")

      assert req.options[:fly_base_url] == "https://custom.api.dev"
    end

    test "accepts custom retry options" do
      req = build_req(retry: :transient, max_retries: 5)

      assert req.options[:fly_retry] == :transient
      assert req.options[:fly_max_retries] == 5
    end
  end

  describe "telemetry helpers" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "capture_telemetry_events/2 captures request events", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{apps: []}))
      end)

      events =
        capture_telemetry_events([:req_fly, :request], fn ->
          req = build_req(base_url: "http://localhost:#{bypass.port}")
          Req.get!(req, url: "/apps")
        end)

      # Should capture both start and stop events
      event_names = Enum.map(events, fn {name, _, _} -> name end)
      assert [:req_fly, :request, :start] in event_names
      assert [:req_fly, :request, :stop] in event_names
    end

    test "assert_telemetry_event/3 validates event metadata", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{apps: []}))
      end)

      events =
        capture_telemetry_events([:req_fly, :request], fn ->
          req = build_req(base_url: "http://localhost:#{bypass.port}")
          Req.get!(req, url: "/apps")
        end)

      # Assert start event
      assert_telemetry_event(events, [:req_fly, :request, :start], %{
        method: :get
      })

      # Assert stop event with status
      assert_telemetry_event(events, [:req_fly, :request, :stop], %{
        method: :get,
        status: 200
      })
    end

    test "telemetry events include URL information", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps/my-app-production", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{name: "my-app-production"}))
      end)

      events =
        capture_telemetry_events([:req_fly, :request], fn ->
          req = build_req(base_url: "http://localhost:#{bypass.port}")
          Req.get!(req, url: "/apps/my-app-production")
        end)

      # Find the stop event
      {_name, _measurements, metadata} =
        Enum.find(events, fn {name, _, _} ->
          name == [:req_fly, :request, :stop]
        end)

      assert metadata.url =~ "my-app-production"
    end

    test "telemetry events include duration measurements", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{apps: []}))
      end)

      events =
        capture_telemetry_events([:req_fly, :request], fn ->
          req = build_req(base_url: "http://localhost:#{bypass.port}")
          Req.get!(req, url: "/apps")
        end)

      # Find the stop event
      {_name, measurements, _metadata} =
        Enum.find(events, fn {name, _, _} ->
          name == [:req_fly, :request, :stop]
        end)

      assert is_integer(measurements.duration)
      assert measurements.duration > 0
    end
  end

  describe "Authorization header filtering" do
    test "cassettes do not contain real authorization tokens" do
      # Read the cassette file directly
      cassette_path =
        Path.join([
          File.cwd!(),
          "test",
          "fixtures",
          "vcr_cassettes",
          "apps",
          "list_personal.json"
        ])

      cassette_content = File.read!(cassette_path)

      # Should not contain "Bearer" followed by a real token
      # (ExVCR filters this to "Bearer [FILTERED]")
      refute cassette_content =~ ~r/Bearer [A-Za-z0-9_-]{20,}/
    end
  end

  describe "integration with ReqFly modules" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "works with ReqFly.request/4 helper", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{total_apps: 2, apps: []}))
      end)

      req = build_req(base_url: "http://localhost:#{bypass.port}")
      {:ok, body} = ReqFly.request(req, :get, "/apps")

      assert is_map(body)
      assert body["total_apps"] == 2
    end

    test "handles error responses", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/apps/nonexistent", fn conn ->
        Plug.Conn.resp(conn, 404, Jason.encode!(%{error: "not_found"}))
      end)

      req = build_req(base_url: "http://localhost:#{bypass.port}")
      result = ReqFly.request(req, :get, "/apps/nonexistent")

      assert {:error, %ReqFly.Error{status: 404}} = result
    end
  end
end
