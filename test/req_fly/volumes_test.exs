defmodule ReqFly.VolumesTest do
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
    test "lists volumes successfully", %{bypass: bypass, req: req} do
      volumes = [
        %{"id" => "vol_1234567890", "name" => "data_volume", "size_gb" => 10},
        %{"id" => "vol_0987654321", "name" => "backup_volume", "size_gb" => 20}
      ]

      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/volumes", fn conn ->
        json_response(conn, 200, Jason.encode!(volumes))
      end)

      assert {:ok, ^volumes} = ReqFly.Volumes.list(req, app_name: "my-app")
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.list(req, [])
      end
    end

    test "raises when app_name is empty string", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.list(req, app_name: "")
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "GET", "/v1/apps/nonexistent/volumes", fn conn ->
        error = %{"error" => "not_found", "message" => "App not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "App not found"}} =
               ReqFly.Volumes.list(req, app_name: "nonexistent")
    end
  end

  describe "create/2" do
    test "creates a volume successfully", %{bypass: bypass, req: req} do
      volume = %{
        "id" => "vol_1234567890",
        "name" => "data_volume",
        "region" => "sjc",
        "size_gb" => 10
      }

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/volumes", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "data_volume"
        assert payload["region"] == "sjc"
        assert payload["size_gb"] == 10

        json_response(conn, 201, Jason.encode!(volume))
      end)

      assert {:ok, ^volume} =
               ReqFly.Volumes.create(req,
                 app_name: "my-app",
                 name: "data_volume",
                 region: "sjc",
                 size_gb: 10
               )
    end

    test "creates a volume with additional parameters", %{bypass: bypass, req: req} do
      volume = %{
        "id" => "vol_1234567890",
        "name" => "data_volume",
        "region" => "sjc",
        "size_gb" => 10,
        "snapshot_retention" => 5
      }

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/volumes", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["name"] == "data_volume"
        assert payload["region"] == "sjc"
        assert payload["size_gb"] == 10
        assert payload["snapshot_retention"] == 5

        json_response(conn, 201, Jason.encode!(volume))
      end)

      assert {:ok, ^volume} =
               ReqFly.Volumes.create(req,
                 app_name: "my-app",
                 name: "data_volume",
                 region: "sjc",
                 size_gb: 10,
                 snapshot_retention: 5
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.create(req,
          name: "data_volume",
          region: "sjc",
          size_gb: 10
        )
      end
    end

    test "raises when name is missing", %{req: req} do
      assert_raise ArgumentError, "name is required", fn ->
        ReqFly.Volumes.create(req,
          app_name: "my-app",
          region: "sjc",
          size_gb: 10
        )
      end
    end

    test "raises when region is missing", %{req: req} do
      assert_raise ArgumentError, "region is required", fn ->
        ReqFly.Volumes.create(req,
          app_name: "my-app",
          name: "data_volume",
          size_gb: 10
        )
      end
    end

    test "raises when size_gb is missing", %{req: req} do
      assert_raise ArgumentError, "size_gb is required", fn ->
        ReqFly.Volumes.create(req,
          app_name: "my-app",
          name: "data_volume",
          region: "sjc"
        )
      end
    end

    test "raises when size_gb is not an integer", %{req: req} do
      assert_raise ArgumentError, "size_gb must be a positive integer", fn ->
        ReqFly.Volumes.create(req,
          app_name: "my-app",
          name: "data_volume",
          region: "sjc",
          size_gb: "10"
        )
      end
    end

    test "raises when size_gb is zero", %{req: req} do
      assert_raise ArgumentError, "size_gb must be a positive integer", fn ->
        ReqFly.Volumes.create(req,
          app_name: "my-app",
          name: "data_volume",
          region: "sjc",
          size_gb: 0
        )
      end
    end

    test "raises when size_gb is negative", %{req: req} do
      assert_raise ArgumentError, "size_gb must be a positive integer", fn ->
        ReqFly.Volumes.create(req,
          app_name: "my-app",
          name: "data_volume",
          region: "sjc",
          size_gb: -10
        )
      end
    end

    test "handles 400 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "POST", "/v1/apps/my-app/volumes", fn conn ->
        error = %{"error" => "bad_request", "message" => "Invalid volume configuration"}
        json_response(conn, 400, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 400, reason: "Invalid volume configuration"}} =
               ReqFly.Volumes.create(req,
                 app_name: "my-app",
                 name: "data_volume",
                 region: "sjc",
                 size_gb: 10
               )
    end
  end

  describe "get/2" do
    test "gets volume details successfully", %{bypass: bypass, req: req} do
      volume = %{
        "id" => "vol_1234567890",
        "name" => "data_volume",
        "region" => "sjc",
        "size_gb" => 10
      }

      Bypass.expect_once(bypass, "GET", "/v1/apps/my-app/volumes/vol_1234567890", fn conn ->
        json_response(conn, 200, Jason.encode!(volume))
      end)

      assert {:ok, ^volume} =
               ReqFly.Volumes.get(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.get(req, volume_id: "vol_1234567890")
      end
    end

    test "raises when volume_id is missing", %{req: req} do
      assert_raise ArgumentError, "volume_id is required", fn ->
        ReqFly.Volumes.get(req, app_name: "my-app")
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "GET", "/v1/apps/my-app/volumes/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "Volume not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "Volume not found"}} =
               ReqFly.Volumes.get(req,
                 app_name: "my-app",
                 volume_id: "nonexistent"
               )
    end
  end

  describe "update/2" do
    test "updates a volume successfully", %{bypass: bypass, req: req} do
      volume = %{
        "id" => "vol_1234567890",
        "name" => "data_volume",
        "snapshot_retention" => 5
      }

      Bypass.expect_once(bypass, "POST", "/v1/apps/my-app/volumes/vol_1234567890", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["snapshot_retention"] == 5

        json_response(conn, 200, Jason.encode!(volume))
      end)

      assert {:ok, ^volume} =
               ReqFly.Volumes.update(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890",
                 snapshot_retention: 5
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.update(req,
          volume_id: "vol_1234567890",
          snapshot_retention: 5
        )
      end
    end

    test "raises when volume_id is missing", %{req: req} do
      assert_raise ArgumentError, "volume_id is required", fn ->
        ReqFly.Volumes.update(req,
          app_name: "my-app",
          snapshot_retention: 5
        )
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "POST", "/v1/apps/my-app/volumes/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "Volume not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "Volume not found"}} =
               ReqFly.Volumes.update(req,
                 app_name: "my-app",
                 volume_id: "nonexistent",
                 snapshot_retention: 5
               )
    end
  end

  describe "delete/2" do
    test "deletes a volume successfully", %{bypass: bypass, req: req} do
      response = %{"status" => "deleted"}

      Bypass.expect_once(
        bypass,
        "DELETE",
        "/v1/apps/my-app/volumes/vol_1234567890",
        fn conn ->
          json_response(conn, 200, Jason.encode!(response))
        end
      )

      assert {:ok, ^response} =
               ReqFly.Volumes.delete(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.delete(req, volume_id: "vol_1234567890")
      end
    end

    test "raises when volume_id is missing", %{req: req} do
      assert_raise ArgumentError, "volume_id is required", fn ->
        ReqFly.Volumes.delete(req, app_name: "my-app")
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "DELETE", "/v1/apps/my-app/volumes/nonexistent", fn conn ->
        error = %{"error" => "not_found", "message" => "Volume not found"}
        json_response(conn, 404, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 404, reason: "Volume not found"}} =
               ReqFly.Volumes.delete(req,
                 app_name: "my-app",
                 volume_id: "nonexistent"
               )
    end

    test "handles 409 error for volumes in use", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "DELETE", "/v1/apps/my-app/volumes/vol_1234567890", fn conn ->
        error = %{"error" => "conflict", "message" => "Volume is in use"}
        json_response(conn, 409, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 409, reason: "Volume is in use"}} =
               ReqFly.Volumes.delete(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890"
               )
    end
  end

  describe "extend/2" do
    test "extends a volume successfully", %{bypass: bypass, req: req} do
      volume = %{
        "id" => "vol_1234567890",
        "name" => "data_volume",
        "size_gb" => 20
      }

      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/apps/my-app/volumes/vol_1234567890/extend",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          assert payload["size_gb"] == 20

          json_response(conn, 200, Jason.encode!(volume))
        end
      )

      assert {:ok, ^volume} =
               ReqFly.Volumes.extend(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890",
                 size_gb: 20
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.extend(req,
          volume_id: "vol_1234567890",
          size_gb: 20
        )
      end
    end

    test "raises when volume_id is missing", %{req: req} do
      assert_raise ArgumentError, "volume_id is required", fn ->
        ReqFly.Volumes.extend(req,
          app_name: "my-app",
          size_gb: 20
        )
      end
    end

    test "raises when size_gb is missing", %{req: req} do
      assert_raise ArgumentError, "size_gb is required", fn ->
        ReqFly.Volumes.extend(req,
          app_name: "my-app",
          volume_id: "vol_1234567890"
        )
      end
    end

    test "raises when size_gb is not an integer", %{req: req} do
      assert_raise ArgumentError, "size_gb must be a positive integer", fn ->
        ReqFly.Volumes.extend(req,
          app_name: "my-app",
          volume_id: "vol_1234567890",
          size_gb: "20"
        )
      end
    end

    test "raises when size_gb is zero", %{req: req} do
      assert_raise ArgumentError, "size_gb must be a positive integer", fn ->
        ReqFly.Volumes.extend(req,
          app_name: "my-app",
          volume_id: "vol_1234567890",
          size_gb: 0
        )
      end
    end

    test "raises when size_gb is negative", %{req: req} do
      assert_raise ArgumentError, "size_gb must be a positive integer", fn ->
        ReqFly.Volumes.extend(req,
          app_name: "my-app",
          volume_id: "vol_1234567890",
          size_gb: -10
        )
      end
    end

    test "handles 400 error for invalid size", %{bypass: bypass, req: req} do
      Bypass.expect(bypass, "POST", "/v1/apps/my-app/volumes/vol_1234567890/extend", fn conn ->
        error = %{"error" => "bad_request", "message" => "Size must be larger than current size"}
        json_response(conn, 400, Jason.encode!(error))
      end)

      assert {:error, %ReqFly.Error{status: 400, reason: "Size must be larger than current size"}} =
               ReqFly.Volumes.extend(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890",
                 size_gb: 5
               )
    end
  end

  describe "list_snapshots/2" do
    test "lists snapshots successfully", %{bypass: bypass, req: req} do
      snapshots = [
        %{"id" => "snap_1", "created_at" => "2024-01-01T00:00:00Z"},
        %{"id" => "snap_2", "created_at" => "2024-01-02T00:00:00Z"}
      ]

      Bypass.expect_once(
        bypass,
        "GET",
        "/v1/apps/my-app/volumes/vol_1234567890/snapshots",
        fn conn ->
          json_response(conn, 200, Jason.encode!(snapshots))
        end
      )

      assert {:ok, ^snapshots} =
               ReqFly.Volumes.list_snapshots(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.list_snapshots(req, volume_id: "vol_1234567890")
      end
    end

    test "raises when volume_id is missing", %{req: req} do
      assert_raise ArgumentError, "volume_id is required", fn ->
        ReqFly.Volumes.list_snapshots(req, app_name: "my-app")
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(
        bypass,
        "GET",
        "/v1/apps/my-app/volumes/nonexistent/snapshots",
        fn conn ->
          error = %{"error" => "not_found", "message" => "Volume not found"}
          json_response(conn, 404, Jason.encode!(error))
        end
      )

      assert {:error, %ReqFly.Error{status: 404, reason: "Volume not found"}} =
               ReqFly.Volumes.list_snapshots(req,
                 app_name: "my-app",
                 volume_id: "nonexistent"
               )
    end
  end

  describe "create_snapshot/2" do
    test "creates a snapshot successfully", %{bypass: bypass, req: req} do
      snapshot = %{
        "id" => "snap_1234567890",
        "volume_id" => "vol_1234567890",
        "created_at" => "2024-01-01T00:00:00Z"
      }

      Bypass.expect_once(
        bypass,
        "POST",
        "/v1/apps/my-app/volumes/vol_1234567890/snapshots",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          # Should send empty object
          assert payload == %{}

          json_response(conn, 201, Jason.encode!(snapshot))
        end
      )

      assert {:ok, ^snapshot} =
               ReqFly.Volumes.create_snapshot(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890"
               )
    end

    test "raises when app_name is missing", %{req: req} do
      assert_raise ArgumentError, "app_name is required", fn ->
        ReqFly.Volumes.create_snapshot(req, volume_id: "vol_1234567890")
      end
    end

    test "raises when volume_id is missing", %{req: req} do
      assert_raise ArgumentError, "volume_id is required", fn ->
        ReqFly.Volumes.create_snapshot(req, app_name: "my-app")
      end
    end

    test "handles 404 error", %{bypass: bypass, req: req} do
      Bypass.expect(
        bypass,
        "POST",
        "/v1/apps/my-app/volumes/nonexistent/snapshots",
        fn conn ->
          error = %{"error" => "not_found", "message" => "Volume not found"}
          json_response(conn, 404, Jason.encode!(error))
        end
      )

      assert {:error, %ReqFly.Error{status: 404, reason: "Volume not found"}} =
               ReqFly.Volumes.create_snapshot(req,
                 app_name: "my-app",
                 volume_id: "nonexistent"
               )
    end

    test "handles 500 error", %{bypass: bypass, req: req} do
      Bypass.expect(
        bypass,
        "POST",
        "/v1/apps/my-app/volumes/vol_1234567890/snapshots",
        fn conn ->
          error = %{"error" => "internal_error", "message" => "Failed to create snapshot"}
          json_response(conn, 500, Jason.encode!(error))
        end
      )

      assert {:error, %ReqFly.Error{status: 500, reason: "Failed to create snapshot"}} =
               ReqFly.Volumes.create_snapshot(req,
                 app_name: "my-app",
                 volume_id: "vol_1234567890"
               )
    end
  end
end
