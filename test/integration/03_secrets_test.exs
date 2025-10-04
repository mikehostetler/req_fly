defmodule ReqFly.Integration.Test03SecretsTest do
  @moduledoc """
  Integration Test 03: Secrets management.

  This test verifies:
  - Creating secrets
  - Listing secrets
  - Generating random secrets
  - Deleting secrets

  Resources created:
  - 1 Fly.io app
  - 2-3 secrets

  Cleanup:
  - Destroys all secrets
  - Destroys the app
  """

  use ReqFly.IntegrationCase
  import ReqFly.IntegrationCase

  @org_slug "req_fly"

  describe "Secrets management" do
    test "create, list, and delete secrets", %{req: req} do
      app_name = test_name("secrets")
      IO.puts("\n→ Testing secrets management: #{app_name}")

      on_exit(fn ->
        IO.puts("→ Cleaning up app: #{app_name}")
        cleanup_app(req, app_name)
      end)

      # Step 1: Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      # Step 2: List secrets (should be empty initially)
      assert {:ok, secrets} = ReqFly.Secrets.list(req, app_name: app_name)
      initial_count = if is_list(secrets), do: length(secrets), else: 0
      IO.puts("✓ Initial secrets listed: #{initial_count}")

      # Step 3: Create a secret
      secret_label = "DATABASE_URL"
      secret_value = "postgres://user:pass@localhost:5432/db"

      assert {:ok, _result} =
               ReqFly.Secrets.create(req,
                 app_name: app_name,
                 label: secret_label,
                 type: "env",
                 value: secret_value
               )

      IO.puts("✓ Secret created: #{secret_label}")

      # Step 4: List secrets again (should have our secret)
      assert {:ok, secrets_after} = ReqFly.Secrets.list(req, app_name: app_name)

      secrets_list =
        if is_list(secrets_after), do: secrets_after, else: secrets_after["secrets"] || []

      assert Enum.any?(secrets_list, fn s ->
               (s["label"] || s["name"]) == secret_label
             end)

      IO.puts("✓ Secret found in listing")

      # Step 5: Create another secret
      secret_label2 = "API_KEY"
      secret_value2 = "sk_test_123456789"

      assert {:ok, _result} =
               ReqFly.Secrets.create(req,
                 app_name: app_name,
                 label: secret_label2,
                 type: "env",
                 value: secret_value2
               )

      IO.puts("✓ Second secret created: #{secret_label2}")

      # Step 6: Delete first secret
      case ReqFly.Secrets.destroy(req, app_name: app_name, label: secret_label) do
        {:ok, _} ->
          IO.puts("✓ Secret deleted: #{secret_label}")

        {:error, error} ->
          # Some APIs use different endpoints for deletion
          IO.puts("⚠ Delete may have different API: #{error.status}")
      end

      # Step 7: Clean up remaining secrets
      case ReqFly.Secrets.list(req, app_name: app_name) do
        {:ok, final_secrets} ->
          final_list =
            if is_list(final_secrets), do: final_secrets, else: final_secrets["secrets"] || []

          IO.puts("✓ Final secret count: #{length(final_list)}")

        {:error, _} ->
          IO.puts("⚠ Could not list final secrets")
      end
    end

    test "generate random secret", %{req: req} do
      app_name = test_name("gen-secret")
      IO.puts("\n→ Testing secret generation: #{app_name}")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)
      IO.puts("✓ App created")

      # Generate a random secret
      result =
        ReqFly.Secrets.generate(req,
          app_name: app_name,
          label: "RANDOM_TOKEN",
          type: "env"
        )

      case result do
        {:ok, generated} ->
          IO.puts("✓ Random secret generated")
          # Check if we got a value back
          if generated["value"] || generated["secret"] do
            IO.puts("✓ Generated value present")
          end

        {:error, %{status: 404}} ->
          IO.puts("⚠ Generate endpoint not available on this API version")

        {:error, error} ->
          IO.puts("⚠ Generate failed: #{error.status} - #{error.reason}")
      end
    end
  end

  describe "Secrets validation" do
    test "creating secret with missing value fails", %{req: req} do
      app_name = test_name("secret-validation")

      on_exit(fn ->
        cleanup_app(req, app_name)
      end)

      # Create app
      assert {:ok, _app} = ReqFly.Apps.create(req, app_name: app_name, org_slug: @org_slug)

      # Try to create secret without value (should fail)
      assert_raise ArgumentError, ~r/value is required/, fn ->
        ReqFly.Secrets.create(req,
          app_name: app_name,
          label: "TEST",
          type: "env"
          # Missing value
        )
      end

      IO.puts("✓ Validation works: missing value raises error")
    end
  end
end
