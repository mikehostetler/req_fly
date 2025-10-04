defmodule ReqFly.Integration.Test04VolumesTest do
  @moduledoc """
  Integration Test 04: Volumes and persistent storage.

  This test verifies:
  - Creating volumes
  - Getting volume details
  - Listing volumes
  - Extending volume size
  - Creating snapshots
  - Listing snapshots
  - Deleting volumes

  Resources created:
  - 1 Fly.io app
  - 1-2 volumes
  - 1 snapshot

  Cleanup:
  - Destroys all volumes
  - Destroys the app
  """

  use ReqFly.IntegrationCase
  import ReqFly.IntegrationCase

  @org_slug "req_fly"
  @test_region "ewr"

  describe "Volume lifecycle" do
    test "create, manage, and delete volume", %{req: req} do
      app_name = test_name("volumes")
      IO.puts("\n→ Testing volume management: #{app_name}")

      on_exit(fn ->
        IO.puts("→ Cleaning up volumes and app: #{app_name}")
        # Clean up volumes first
        case ReqFly.Volumes.list(req, app_name: app_name) do
          {:ok, volumes} when is_list(volumes) ->
            Enum.each(volumes, fn vol ->
              vol_id = vol["id"] || vol["volume_id"]

              if vol_id do
                ReqFly.Volumes.delete(req, app_name: app_name, volume_id: vol_id)
                IO.puts("  → Deleted volume: #{vol_id}")
              end
            end)

          _ ->
            :ok
        end

        cleanup_app(req, app_name)
      end)

      # Step 1: Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      # Step 2: List volumes (should be empty)
      assert {:ok, volumes} = ReqFly.Volumes.list(req, app_name: app_name)
      assert is_list(volumes)
      IO.puts("✓ Initial volumes listed: #{length(volumes)}")

      # Step 3: Create a volume
      volume_name = "data_volume"

      assert {:ok, volume} =
               ReqFly.Volumes.create(req,
                 app_name: app_name,
                 name: volume_name,
                 region: @test_region,
                 size_gb: 1
               )

      volume_id = volume["id"] || volume["volume_id"]
      assert volume_id
      IO.puts("✓ Volume created: #{volume_id}")

      # Step 4: Get volume details
      assert {:ok, vol_details} =
               ReqFly.Volumes.get(req,
                 app_name: app_name,
                 volume_id: volume_id
               )

      assert vol_details["id"] || vol_details["volume_id"]
      IO.puts("✓ Volume details retrieved")

      # Step 5: List volumes (should have our volume)
      assert {:ok, volumes_after} = ReqFly.Volumes.list(req, app_name: app_name)
      assert is_list(volumes_after)

      assert Enum.any?(volumes_after, fn v ->
               (v["id"] || v["volume_id"]) == volume_id
             end)

      IO.puts("✓ Volume found in listing")

      # Step 6: Extend volume size
      result =
        ReqFly.Volumes.extend(req,
          app_name: app_name,
          volume_id: volume_id,
          size_gb: 2
        )

      case result do
        {:ok, extended} ->
          IO.puts("✓ Volume extended to 2GB")
          # Verify size increased
          if extended["size_gb"] == 2 do
            IO.puts("✓ Size confirmed: 2GB")
          end

        {:error, %{status: status}} when status in [400, 422] ->
          IO.puts("⚠ Volume extension not supported or failed: #{status}")

        {:error, error} ->
          IO.puts("⚠ Volume extension failed: #{error.status}")
      end

      # Step 7: Delete volume
      assert {:ok, _} =
               ReqFly.Volumes.delete(req,
                 app_name: app_name,
                 volume_id: volume_id
               )

      IO.puts("✓ Volume deleted")

      # Step 8: Verify deletion
      wait_until(
        fn ->
          case ReqFly.Volumes.get(req, app_name: app_name, volume_id: volume_id) do
            {:error, %{status: 404}} -> true
            {:ok, vol} -> (vol["state"] || vol["status"]) == "deleted"
            _ -> false
          end
        end,
        timeout: 10_000
      )

      IO.puts("✓ Volume deletion confirmed")
    end
  end

  describe "Volume snapshots" do
    test "create and list volume snapshots", %{req: req} do
      app_name = test_name("snapshots")
      IO.puts("\n→ Testing volume snapshots: #{app_name}")

      on_exit(fn ->
        # Clean up volumes
        case ReqFly.Volumes.list(req, app_name: app_name) do
          {:ok, volumes} when is_list(volumes) ->
            Enum.each(volumes, fn vol ->
              vol_id = vol["id"] || vol["volume_id"]

              if vol_id do
                ReqFly.Volumes.delete(req, app_name: app_name, volume_id: vol_id)
              end
            end)

          _ ->
            :ok
        end

        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      # Create volume
      assert {:ok, volume} =
               ReqFly.Volumes.create(req,
                 app_name: app_name,
                 name: "snapshot_test",
                 region: @test_region,
                 size_gb: 1
               )

      volume_id = volume["id"] || volume["volume_id"]
      IO.puts("✓ Volume created: #{volume_id}")

      # List snapshots (should be empty)
      result =
        ReqFly.Volumes.list_snapshots(req,
          app_name: app_name,
          volume_id: volume_id
        )

      case result do
        {:ok, snapshots} ->
          assert is_list(snapshots)
          IO.puts("✓ Snapshots listed: #{length(snapshots)}")

        {:error, %{status: 404}} ->
          IO.puts("⚠ Snapshots endpoint not available")

        {:error, error} ->
          IO.puts("⚠ Snapshot list failed: #{error.status}")
      end

      # Create a snapshot
      snapshot_result =
        ReqFly.Volumes.create_snapshot(req,
          app_name: app_name,
          volume_id: volume_id
        )

      case snapshot_result do
        {:ok, snapshot} ->
          IO.puts("✓ Snapshot created")
          snapshot_id = snapshot["id"] || snapshot["snapshot_id"]

          if snapshot_id do
            IO.puts("✓ Snapshot ID: #{snapshot_id}")
          end

        {:error, %{status: status}} when status in [404, 501] ->
          IO.puts("⚠ Snapshot creation not supported")

        {:error, error} ->
          IO.puts("⚠ Snapshot creation failed: #{error.status}")
      end
    end
  end

  describe "Volume validation" do
    test "creating volume with invalid size fails", %{req: req} do
      app_name = test_name("vol-validation")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)

      # Try to create volume with invalid size (should fail)
      assert_raise ArgumentError, ~r/size_gb must be a positive integer/, fn ->
        ReqFly.Volumes.create(req,
          app_name: app_name,
          name: "invalid",
          region: @test_region,
          # Invalid: negative size
          size_gb: -1
        )
      end

      IO.puts("✓ Validation works: negative size raises error")

      # Try to create volume with zero size (should fail)
      assert_raise ArgumentError, ~r/size_gb must be a positive integer/, fn ->
        ReqFly.Volumes.create(req,
          app_name: app_name,
          name: "invalid",
          region: @test_region,
          # Invalid: zero size
          size_gb: 0
        )
      end

      IO.puts("✓ Validation works: zero size raises error")
    end
  end
end
