defmodule ReqFly.AppsTest do
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
    test "lists apps successfully without org_slug", %{bypass: bypass, req: req} do
      apps = [
        %{"name" => "app-1", "organization" => %{"slug" => "org-1"}},
        %{"name" => "app-2", "organization" => %{"slug" => "org-2"}}
      ]

      Bypass.expect_once(bypass, "GET", "/v1/apps", fn conn ->
        assert conn.query_string == ""
        json_response(conn, 200, Jason.encode!(apps))
      end)

      assert {:ok, ^apps} = ReqFly.Apps.list(req)
    end

    test "lists apps with org_slug filter", %{bypass: bypass, req: req} do
      apps = [
        %{"name" => "app-1", "organization" => %{"slug" => "my-org"}},
        %{"name" => "app-2", "organization" => %{"slug" => "my-org"}}
      ]

      Bypass.expect_once(bypass, "GET", "/v1/apps", fn conn ->
        assert conn.query_string == "org_slug=my-org"
        json_response(conn, 200, Jason.encode!(apps))
      end)

      assert {:ok, ^apps} = ReqFly.Apps.list(req, org_slug: "my-org")
    end

    test "handles 500 error", %{bypass: bypass} do
      req_no_retry =
        Req.new()
        |> ReqFly.attach(
          token: "test",
          base_url: "http://localhost:#{bypass.port}/v1",
          max_retries: 1,
          retry_delay: fn _ -> 1 end
        )

      Bypass.expect(bypass, "GET", "/v1/apps", fn conn ->
        error = %{"error" => "internal_error", "message" => "Server error"}
        json_response(conn, 500, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 500, reason: "Server error"}} = ReqFly.Apps.list(req_no_retry)
    end
  end

  describe "create/2" do
    test "creates an app successfully", %{bypass: bypass, req: req} do
      app = %{"name" => "my-app", "organization" => %{"slug" => "my-org"}}

      Bypass.expect_once(bypass, "POST", "/v1/apps", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["app_name"] == "my-app"
        assert payload["org_slug"] == "my-org"

        json_response(conn, 201, Jason.encode!(app))
      end)

      assert {:ok, ^app} = ReqFly.Apps.create(req, app_name: "my-app", org_slug: "my-org")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Apps.create(req, org_slug: "my-org")
      end
    end

    test "raises when app_name is empty", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Apps.create(req, app_name: "", org_slug: "my-org")
      end
    end

    test "raises when org_slug is missing", %{req: req} do
      assert_raise ArgumentError, "org_slug is required", fn ->
        ReqFly.Apps.create(req, app_name: "my-app")
      end
    end

    test "raises when org_slug is empty", %{req: req} do
      assert_raise ArgumentError, "org_slug is required", fn ->
        ReqFly.Apps.create(req, app_name: "my-app", org_slug: "")
      end
    end

    test "handles 400 error for invalid input", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "POST", "/v1/apps", fn conn ->
        error = %{"error" => "invalid_input", "message" => "App name already taken"}
        json_response(conn, 400, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 400, reason: "App name already taken"}} =
               ReqFly.Apps.create(req, app_name: "my-app", org_slug: "my-org")
    end
  end

  describe "get/2" do
    test "gets an app successfully", %{bypass: bypass, req: req} do
      app = %{"name" => "my-app", "organization" => %{"slug" => "my-org"}}

      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app", fn conn ->
        json_response(conn, 200, Jason.encode!(app))
      end)

      assert {:ok, ^app} = ReqFly.Apps.get(req, "my-app")
    end

    test "handles 404 when app not found", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "GET", "/v1/apps/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "App not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "App not found"}} =
               ReqFly.Apps.get(req, "nonexistent")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Apps.get(req, nil)
      end
    end

    test "raises when app_name is empty", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Apps.get(req, "")
      end
    end
  end

  describe "destroy/2" do
    test "destroys an app successfully", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "DELETE", "/v1/apps/my-app", fn conn ->
        json_response(conn, 202, Jason.encode!(%{"status" => "deleted"}))
      end)

      assert {:ok, %{"status" => "deleted"}} = ReqFly.Apps.destroy(req, "my-app")
    end

    test "handles 404 when app not found", %{bypass: bypass, req: req} do
      Bypass.expect_once(bypass, "DELETE", "/v1/apps/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "App not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "App not found"}} =
               ReqFly.Apps.destroy(req, "nonexistent")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Apps.destroy(req, nil)
      end
    end

    test "raises when app_name is empty", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Apps.destroy(req, "")
      end
    end
  end
end
