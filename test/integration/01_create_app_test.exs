defmodule ReqFly.Integration.Test01CreateAppTest do
  @moduledoc """
  Integration Test 01: Create and manage a Fly.io app.

  This test verifies:
  - Creating a new app
  - Getting app details
  - Listing apps
  - Destroying an app

  Resources created:
  - 1 Fly.io app

  Cleanup:
  - Destroys the app after test completes
  """

  use ReqFly.IntegrationCase
  import ReqFly.IntegrationCase

  @org_slug "req_fly"

  describe "App lifecycle" do
    test "create, get, and destroy an app", %{req: req} do
      # Generate unique app name
      app_name = test_name("app-lifecycle")
      IO.puts("\n→ Creating app: #{app_name}")

      # Cleanup on exit
      on_exit(fn ->
        IO.puts("→ Cleaning up app: #{app_name}")
        cleanup_app(req, app_name)
      end)

      # Step 1: Create app (apps don't need to be "active" to use)
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created: #{app_name}")

      # Step 2: Get app details
      assert {:ok, app_details} = ReqFly.Apps.get(req, app_name)
      assert app_details["name"] == app_name
      IO.puts("✓ App retrieved: #{app_details["name"]}")

      # Step 3: List apps and verify our app is in the list
      assert {:ok, response} = ReqFly.Apps.list(req, org_slug: @org_slug)
      # Response is wrapped: %{"apps" => [...], "total_apps" => N}
      apps = response["apps"] || response
      assert is_list(apps)
      assert Enum.any?(apps, fn a -> a["name"] == app_name end)
      IO.puts("✓ App found in org listing")

      # Step 4: Destroy app
      assert {:ok, _} = ReqFly.Apps.destroy(req, app_name)
      IO.puts("✓ App destroyed: #{app_name}")

      # Step 5: Verify app is eventually gone (may take time to fully delete)
      wait_until(
        fn ->
          case ReqFly.Apps.get(req, app_name) do
            {:error, %{status: 404}} -> true
            {:ok, %{"status" => "suspended"}} -> true
            _ -> false
          end
        end,
        timeout: 10_000
      )

      IO.puts("✓ App confirmed deleted")
    end
  end

  describe "App validation" do
    test "creating duplicate app returns error", %{req: req} do
      app_name = test_name("duplicate")
      IO.puts("\n→ Testing duplicate app creation: #{app_name}")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Create first app
      assert {:ok, _} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ First app created")

      # Try to create duplicate - should fail
      assert {:error, error} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      assert error.status in [400, 409, 422]
      IO.puts("✓ Duplicate creation failed as expected (#{error.status})")
    end
  end
end
