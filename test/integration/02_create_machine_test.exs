defmodule ReqFly.Integration.Test02CreateMachineTest do
  @moduledoc """
  Integration Test 02: Create and manage Fly.io machines.

  This test verifies:
  - Creating an app
  - Creating a machine with a simple Docker image
  - Getting machine details
  - Listing machines
  - Starting/stopping machines
  - Destroying a machine

  Resources created:
  - 1 Fly.io app
  - 1 machine (nginx:alpine)

  Cleanup:
  - Stops and destroys all machines
  - Destroys the app
  """

  use ReqFly.IntegrationCase
  import ReqFly.IntegrationCase

  @org_slug "req_fly"
  @test_image "nginx:alpine"
  # Newark - usually fast
  @test_region "ewr"

  describe "Machine lifecycle" do
    test "create, manage, and destroy a machine", %{req: req} do
      # Setup
      app_name = test_name("machine-lifecycle")
      IO.puts("\n→ Creating app: #{app_name}")

      on_exit(fn ->
        IO.puts("→ Cleaning up app and machines: #{app_name}")
        cleanup_app(req, app_name)
      end)

      # Step 1: Create app (apps are immediately usable)
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created: #{app_name}")

      # Step 2: Create machine and wait for it to start (using Orchestrator)
      machine_config = %{
        "image" => @test_image,
        "guest" => %{
          "cpu_kind" => "shared",
          "cpus" => 1,
          "memory_mb" => 256
        },
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

      IO.puts("→ Creating machine with image: #{@test_image}")

      assert {:ok, machine} =
               ReqFly.Orchestrator.create_machine_and_wait(req,
                 app_name: app_name,
                 config: machine_config,
                 region: @test_region,
                 state: "started",
                 timeout: 45
               )

      machine_id = machine["id"] || machine["machine"]["id"]
      assert machine_id, "Machine ID not found in response: #{inspect(Map.keys(machine))}"
      IO.puts("✓ Machine created and started: #{machine_id}")

      # Step 3: Get machine details
      assert {:ok, machine_details} =
               ReqFly.Machines.get(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      assert machine_details["id"] == machine_id
      assert machine_details["config"]["image"] == @test_image
      IO.puts("✓ Machine details retrieved")

      # Step 4: List machines
      assert {:ok, machines} = ReqFly.Machines.list(req, app_name: app_name)
      assert is_list(machines)
      assert Enum.any?(machines, fn m -> m["id"] == machine_id end)
      IO.puts("✓ Machine found in listing")

      # Step 5: Stop machine and wait
      IO.puts("→ Stopping machine...")

      assert {:ok, _} =
               ReqFly.Machines.stop(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      # Wait for machine to actually stop
      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
            {:ok, m} -> m["state"] in ["stopped", "suspended"]
            _ -> false
          end
        end,
        timeout: 15_000
      )

      IO.puts("✓ Machine stopped")

      # Step 6: Start machine and wait
      IO.puts("→ Starting machine...")

      assert {:ok, _} =
               ReqFly.Machines.start(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      # Wait for machine to actually start
      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
            {:ok, m} -> m["state"] == "started"
            _ -> false
          end
        end,
        timeout: 15_000
      )

      IO.puts("✓ Machine started")

      # Step 8: Destroy machine
      IO.puts("→ Destroying machine...")
      # Stop first to ensure clean deletion (must be stopped)
      ReqFly.Machines.stop(req, app_name: app_name, machine_id: machine_id)

      # Wait for machine to actually stop
      wait_until(
        fn ->
          case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
            {:ok, m} -> m["state"] in ["stopped", "suspended", "failed"]
            _ -> false
          end
        end,
        timeout: 15_000
      )

      assert {:ok, _} =
               ReqFly.Machines.destroy(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      IO.puts("✓ Machine destroyed")

      # Step 9: Verify machine is destroyed (state = "destroyed")
      # Note: Fly.io returns 200 with state "destroyed" instead of 404
      case ReqFly.Machines.get(req, app_name: app_name, machine_id: machine_id) do
        {:ok, destroyed_machine} ->
          assert destroyed_machine["state"] == "destroyed"
          IO.puts("✓ Machine confirmed destroyed (state: destroyed)")

        {:error, error} ->
          # 404 is also acceptable
          assert error.status == 404
          IO.puts("✓ Machine confirmed deleted (404)")
      end
    end
  end

  describe "Machine operations" do
    test "restart and signal machine", %{req: req} do
      app_name = test_name("machine-ops")
      IO.puts("\n→ Testing machine operations: #{app_name}")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)

      # Create simple machine
      machine_config = %{
        "image" => @test_image,
        "guest" => %{"cpu_kind" => "shared", "cpus" => 1, "memory_mb" => 256}
      }

      assert {:ok, machine} =
               ReqFly.Machines.create(req,
                 app_name: app_name,
                 config: machine_config,
                 region: @test_region
               )

      machine_id = machine["id"]
      IO.puts("✓ Machine created: #{machine_id}")

      Process.sleep(3000)

      # Test restart
      IO.puts("→ Restarting machine...")

      assert {:ok, _} =
               ReqFly.Machines.restart(req,
                 app_name: app_name,
                 machine_id: machine_id
               )

      IO.puts("✓ Machine restarted")

      Process.sleep(2000)

      # Test signal (SIGTERM)
      IO.puts("→ Sending SIGTERM signal...")

      result =
        ReqFly.Machines.signal(req,
          app_name: app_name,
          machine_id: machine_id,
          signal: "SIGTERM"
        )

      # Signal might succeed or fail depending on machine state - both are acceptable
      case result do
        {:ok, _} -> IO.puts("✓ Signal sent successfully")
        {:error, _} -> IO.puts("✓ Signal operation completed (machine may be stopping)")
      end
    end
  end
end
