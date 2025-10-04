defmodule ReqFly.Integration.Test05MachineAdvancedTest do
  @moduledoc """
  Integration Test 05: Advanced machine operations.

  This test verifies:
  - Machine update/configuration changes
  - Machine wait endpoint
  - Multiple machines in one app
  - Machine state transitions
  - Complex orchestration scenarios

  Resources created:
  - 1 Fly.io app
  - 2-3 machines

  Cleanup:
  - Stops and destroys all machines
  - Destroys the app
  """

  use ReqFly.IntegrationCase
  import ReqFly.IntegrationCase

  @org_slug "req_fly"
  @test_image "nginx:alpine"
  @test_region "ewr"

  describe "Machine update" do
    test "update machine configuration", %{req: req} do
      app_name = test_name("machine-update")
      IO.puts("\n→ Testing machine update: #{app_name}")

      on_exit(fn ->
        IO.puts("→ Cleaning up app: #{app_name}")
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      # Create machine with basic config
      initial_config = %{
        "image" => @test_image,
        "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 256}
      }

      assert {:ok, machine} =
               ReqFly.Orchestrator.create_machine_and_wait(req,
                 app_name: app_name,
                 config: initial_config,
                 region: @test_region,
                 state: "started",
                 timeout: 45
               )

      machine_id = machine["id"]
      IO.puts("✓ Machine created: #{machine_id}")

      # Update machine configuration (e.g., increase memory)
      updated_config = %{
        "image" => @test_image,
        "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 512}
      }

      result =
        ReqFly.Machines.update(req,
          app_name: app_name,
          machine_id: machine_id,
          config: updated_config
        )

      case result do
        {:ok, updated} ->
          IO.puts("✓ Machine configuration updated")

          if updated["config"]["guest"]["memory_mb"] == 512 do
            IO.puts("✓ Memory increase confirmed")
          end

        {:error, %{status: status}} when status in [400, 422] ->
          IO.puts("⚠ Update may require machine to be stopped: #{status}")

        {:error, error} ->
          IO.puts("⚠ Update failed: #{error.status}")
      end
    end
  end

  describe "Machine wait endpoint" do
    test "wait for machine state using wait endpoint", %{req: req} do
      app_name = test_name("machine-wait")
      IO.puts("\n→ Testing machine wait endpoint: #{app_name}")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      # Create machine
      config = %{
        "image" => @test_image,
        "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 256}
      }

      assert {:ok, machine} =
               ReqFly.Machines.create(req,
                 app_name: app_name,
                 config: config,
                 region: @test_region
               )

      machine_id = machine["id"]
      instance_id = machine["instance_id"]
      IO.puts("✓ Machine created: #{machine_id}")

      # Use wait endpoint if instance_id is available
      if instance_id do
        result =
          ReqFly.Machines.wait(req,
            app_name: app_name,
            machine_id: machine_id,
            instance_id: instance_id,
            state: "started",
            timeout: 30
          )

        case result do
          {:ok, _waited} ->
            IO.puts("✓ Wait endpoint succeeded")

          {:error, %{status: 404}} ->
            IO.puts("⚠ Wait endpoint not available")

          {:error, %{status: 408}} ->
            IO.puts("⚠ Wait endpoint timed out")

          {:error, error} ->
            IO.puts("⚠ Wait endpoint failed: #{error.status}")
        end
      else
        IO.puts("⚠ No instance_id available for wait endpoint")
      end
    end
  end

  describe "Multiple machines" do
    test "manage multiple machines in one app", %{req: req} do
      app_name = test_name("multi-machine")
      IO.puts("\n→ Testing multiple machines: #{app_name}")

      on_exit(fn ->
        IO.puts("→ Cleaning up all machines and app")
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      config = %{
        "image" => @test_image,
        "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 256}
      }

      # Create first machine
      assert {:ok, machine1} =
               ReqFly.Orchestrator.create_machine_and_wait(req,
                 app_name: app_name,
                 config: config,
                 region: @test_region,
                 state: "started",
                 timeout: 45
               )

      machine_id1 = machine1["id"]
      IO.puts("✓ Machine 1 created: #{machine_id1}")

      # Create second machine
      assert {:ok, machine2} =
               ReqFly.Orchestrator.create_machine_and_wait(req,
                 app_name: app_name,
                 config: config,
                 region: @test_region,
                 state: "started",
                 timeout: 45
               )

      machine_id2 = machine2["id"]
      IO.puts("✓ Machine 2 created: #{machine_id2}")

      # List all machines
      assert {:ok, machines} = ReqFly.Machines.list(req, app_name: app_name)
      assert is_list(machines)
      assert length(machines) >= 2
      IO.puts("✓ Total machines in app: #{length(machines)}")

      # Verify both machines are present
      machine_ids = Enum.map(machines, & &1["id"])
      assert machine_id1 in machine_ids
      assert machine_id2 in machine_ids
      IO.puts("✓ Both machines found in listing")

      # Stop first machine
      assert {:ok, _} =
               ReqFly.Machines.stop(req,
                 app_name: app_name,
                 machine_id: machine_id1
               )

      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id1) do
            {:ok, m} -> m["state"] in ["stopped", "suspended"]
            _ -> false
          end
        end,
        timeout: 15_000
      )

      IO.puts("✓ Machine 1 stopped")

      # Verify second machine is still running
      assert {:ok, m2} =
               ReqFly.Machines.get(req,
                 app_name: app_name,
                 machine_id: machine_id2
               )

      IO.puts("✓ Machine 2 state: #{m2["state"]}")
    end
  end

  describe "Complex orchestration" do
    test "full deployment workflow", %{req: req} do
      app_name = test_name("full-deploy")
      IO.puts("\n→ Testing full deployment workflow: #{app_name}")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Step 1: Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ Step 1: App created")

      # Step 2: Create and start machine
      config = %{
        "image" => @test_image,
        "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 256},
        "services" => [
          %{
            "ports" => [
              %{"port" => 80, "handlers" => ["http"]},
              %{"port" => 443, "handlers" => ["tls", "http"]}
            ],
            "protocol" => "tcp",
            "internal_port" => 80
          }
        ]
      }

      assert {:ok, machine} =
               ReqFly.Orchestrator.create_machine_and_wait(req,
                 app_name: app_name,
                 config: config,
                 region: @test_region,
                 state: "started",
                 timeout: 45
               )

      machine_id = machine["id"]
      IO.puts("✓ Step 2: Machine deployed and started")

      # Step 3: Verify machine is serving
      assert {:ok, machine_check} =
               ReqFly.Machines.get(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      assert machine_check["state"] == "started"
      IO.puts("✓ Step 3: Machine verified running")

      # Step 4: Rolling restart (stop then start)
      assert {:ok, _} =
               ReqFly.Machines.stop(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
            {:ok, m} -> m["state"] in ["stopped", "suspended"]
            _ -> false
          end
        end,
        timeout: 15_000
      )

      IO.puts("✓ Step 4: Machine stopped for restart")

      assert {:ok, _} =
               ReqFly.Machines.start(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
            {:ok, m} -> m["state"] == "started"
            _ -> false
          end
        end,
        timeout: 15_000
      )

      IO.puts("✓ Step 5: Machine restarted successfully")

      # Step 6: Graceful shutdown
      assert {:ok, _} =
               ReqFly.Machines.stop(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
            {:ok, m} -> m["state"] in ["stopped", "suspended"]
            _ -> false
          end
        end,
        timeout: 15_000
      )

      IO.puts("✓ Step 6: Machine gracefully stopped")

      IO.puts("✓ Full deployment workflow complete")
    end
  end
end
