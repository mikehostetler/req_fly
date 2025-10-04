defmodule ReqFly.SecretsTest do
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
    test "lists secrets successfully", %{bypass: bypass, req: req} do
      secrets = [
        %{"label" => "DATABASE_URL", "type" => "env"},
        %{"label" => "SECRET_KEY", "type" => "env"}
      ]

      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/secrets", fn conn ->
        json_response(conn, 200, Jason.encode!(secrets))
      end)

      assert {:ok, ^secrets} = ReqFly.Secrets.list(req, app_name: "my-app")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Secrets.list(req, [])
      end
    end

    test "raises when app_name is empty string", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Secrets.list(req, app_name: "")
      end
    end

    test "raises when app_name is not a string", %{req: req} do
      assert_raise ArgumentError, "app_name must be a non-empty string", fn ->
        ReqFly.Secrets.list(req, app_name: 123)
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "GET", "/v1/apps/nonexistent/secrets", fn conn ->
        error = %{"error" => "not_found", "message" => "App not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "App not found"}} =
               ReqFly.Secrets.list(req, app_name: "nonexistent")
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

      Bypass.expect(bypass, "GET", "/v1/apps/my-app/secrets", fn conn ->
        error = %{"error" => "internal_error", "message" => "Server error"}
        json_response(conn, 500, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 500, reason: "Server error"}} =
               ReqFly.Secrets.list(req_no_retry, app_name: "my-app")
    end
  end

  describe "create/2" do
    test "creates a secret successfully", %{bypass: bypass, req: req} do
      secret = %{"label" => "DATABASE_URL", "type" => "env", "digest" => "abc123"}

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/secrets", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["label"] == "DATABASE_URL"
        assert payload["type"] == "env"
        assert payload["value"] == "postgres://localhost/db"

        json_response(conn, 201, Jason.encode!(secret))
      end)

      assert {:ok, ^secret} =
               ReqFly.Secrets.create(req,
                 app_name: "my-app",
                 label: "DATABASE_URL",
                 type: "env",
                 value: "postgres://localhost/db"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Secrets.create(req,
          label: "SECRET",
          type: "env",
          value: "value"
        )
      end
    end

    test "raises when label is missing", %{req: req} do
      assert_raise ArgumentError, "label is required", fn ->
        ReqFly.Secrets.create(req,
          app_name: "my-app",
          type: "env",
          value: "value"
        )
      end
    end

    test "raises when type is missing", %{req: req} do
      assert_raise ArgumentError, "type is required", fn ->
        ReqFly.Secrets.create(req,
          app_name: "my-app",
          label: "SECRET",
          value: "value"
        )
      end
    end

    test "raises when value is missing", %{req: req} do
      assert_raise ArgumentError, "value is required", fn ->
        ReqFly.Secrets.create(req,
          app_name: "my-app",
          label: "SECRET",
          type: "env"
        )
      end
    end

    test "raises when label is empty string", %{req: req} do
      assert_raise ArgumentError, "label is required", fn ->
        ReqFly.Secrets.create(req,
          app_name: "my-app",
          label: "",
          type: "env",
          value: "value"
        )
      end
    end

    test "handles 400 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "POST", "/v1/apps/my-app/secrets", fn conn ->
        error = %{"error" => "bad_request", "message" => "Invalid secret configuration"}
        json_response(conn, 400, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 400, reason: "Invalid secret configuration"}} =
               ReqFly.Secrets.create(req,
                 app_name: "my-app",
                 label: "SECRET",
                 type: "env",
                 value: "value"
               )
    end
  end

  describe "generate/2" do
    test "generates a secret successfully", %{bypass: bypass, req: req} do
      secret = %{
        "label" => "SECRET_KEY",
        "type" => "env",
        "digest" => "xyz789",
        "value" => "generated_random_value"
      }

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/secrets/generate", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["label"] == "SECRET_KEY"
        assert payload["type"] == "env"
        refute Map.has_key?(payload, "value")

        json_response(conn, 201, Jason.encode!(secret))
      end)

      assert {:ok, ^secret} =
               ReqFly.Secrets.generate(req,
                 app_name: "my-app",
                 label: "SECRET_KEY",
                 type: "env"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Secrets.generate(req,
          label: "SECRET_KEY",
          type: "env"
        )
      end
    end

    test "raises when label is missing", %{req: req} do
      assert_raise ArgumentError, "label is required", fn ->
        ReqFly.Secrets.generate(req,
          app_name: "my-app",
          type: "env"
        )
      end
    end

    test "raises when type is missing", %{req: req} do
      assert_raise ArgumentError, "type is required", fn ->
        ReqFly.Secrets.generate(req,
          app_name: "my-app",
          label: "SECRET_KEY"
        )
      end
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

      Bypass.expect(bypass, "POST", "/v1/apps/my-app/secrets/generate", fn conn ->
        error = %{"error" => "internal_error", "message" => "Failed to generate secret"}
        json_response(conn, 500, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 500, reason: "Failed to generate secret"}} =
               ReqFly.Secrets.generate(req_no_retry,
                 app_name: "my-app",
                 label: "SECRET_KEY",
                 type: "env"
               )
    end
  end

  describe "destroy/2" do
    test "destroys a secret successfully", %{bypass: bypass, req: req} do
      response = %{"status" => "deleted"}

      Bypass.expect_once(bypass, "DELETE", "/v1/apps/my-app/secrets/OLD_SECRET", fn conn ->
        json_response(conn, 200, Jason.encode!(response))
      end)

      assert {:ok, ^response} =
               ReqFly.Secrets.destroy(req,
                 app_name: "my-app",
                 label: "OLD_SECRET"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Secrets.destroy(req, label: "OLD_SECRET")
      end
    end

    test "raises when label is missing", %{req: req} do
      assert_raise ArgumentError, "label is required", fn ->
        ReqFly.Secrets.destroy(req, app_name: "my-app")
      end
    end

    test "raises when label is empty string", %{req: req} do
      assert_raise ArgumentError, "label is required", fn ->
        ReqFly.Secrets.destroy(req, app_name: "my-app", label: "")
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "DELETE", "/v1/apps/my-app/secrets/NONEXISTENT", fn conn ->
        error = %{"error" => "not_found", "message" => "Secret not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "Secret not found"}} =
               ReqFly.Secrets.destroy(req,
                 app_name: "my-app",
                 label: "NONEXISTENT"
               )
    end

    test "handles 403 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "DELETE", "/v1/apps/my-app/secrets/PROTECTED", fn conn ->
        error = %{"error" => "forbidden", "message" => "Cannot delete protected secret"}
        json_response(conn, 403, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 403, reason: "Cannot delete protected secret"}} =
               ReqFly.Secrets.destroy(req,
                 app_name: "my-app",
                 label: "PROTECTED"
               )
    end
  end
end
