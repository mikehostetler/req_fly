# Integration Tests

Live integration tests for ReqFly that interact with the real Fly.io API.

## ⚠️ Important

These tests:
- **Create real Fly.io resources** (apps, machines, volumes, etc.)
- **Cost real money** (though minimal, as resources are cleaned up quickly)
- **Require a valid FLY_API_TOKEN** environment variable
- **Clean up all resources** after each test completes

## Setup

1. Get your Fly.io API token:
   - Go to https://fly.io/user/personal_access_tokens
   - Create a new token (or use an existing one)
   - Copy the token value

2. Set the environment variable:
   ```bash
   export FLY_API_TOKEN="your_token_here"
   ```

3. Ensure you have a Fly.io organization (usually "personal")

## Running Tests

### Run all integration tests sequentially:
```bash
./run_integration_tests.sh
```

### Run a specific test:
```bash
mix test test/integration/01_create_app_test.exs --only integration
```

### Run all integration tests with mix:
```bash
mix test --only integration
```

### Run unit tests only (default):
```bash
mix test
```

## Test Structure

Integration tests are numbered sequentially (01, 02, 03, etc.) and build on each other:

- **01_create_app_test.exs** - Basic app lifecycle (create, get, list, destroy)
- **02_create_machine_test.exs** - Machine lifecycle (create, start, stop, destroy)
- **More tests to come...**

Each test file:
- Is self-contained
- Uses unique resource names with timestamps
- Cleans up ALL resources in `on_exit` callbacks
- Has a 2-minute timeout for slow operations
- Prints progress to help debug issues

## Writing New Integration Tests

1. Create a new file: `test/integration/NN_description_test.exs` (where NN is the next number)

2. Use the template:
   ```elixir
   defmodule ReqFly.Integration.TestNNDescriptionTest do
     use ReqFly.IntegrationCase
     import ReqFly.IntegrationCase

     describe "Feature" do
       test "does something", %{req: req} do
         # Generate unique names
         app_name = test_name("my-feature")
         
         # Setup cleanup
         on_exit(fn ->
           cleanup_app(req, app_name)
         end)
         
         # Test code here...
         assert {:ok, _} = ReqFly.Apps.create(req, 
           app_name: app_name, 
           org_slug: "personal"
         )
       end
     end
   end
   ```

3. **Always clean up resources** - use `on_exit` callbacks

4. **Use helper functions** from `ReqFly.IntegrationCase`:
   - `test_name(prefix)` - Generate unique names
   - `cleanup_app(req, app_name)` - Clean up app and all resources
   - `wait_until(fun, opts)` - Poll until condition is true

## Troubleshooting

### Test hangs or times out
- Increase timeout: `@moduletag timeout: 180_000` (3 minutes)
- Check Fly.io dashboard for stuck resources
- Manually delete stuck resources if needed

### Authentication errors
- Verify `FLY_API_TOKEN` is set correctly
- Check token hasn't expired
- Ensure token has correct permissions

### Resource cleanup failures
- Check test output for specific errors
- Manually verify resources in Fly.io dashboard
- Some resources may take time to fully delete

### Rate limiting
- The bash script adds 2-second delays between tests
- If you hit rate limits, increase the delay
- Run tests individually with longer waits

## Cost Considerations

Integration tests use minimal resources:
- **Apps**: Free to create
- **Machines**: Billed per second, usually <$0.01 per test
- **Volumes**: Billed per GB-hour, minimal for short tests

Total cost for full suite: **~$0.05-0.10**

Resources are cleaned up immediately to minimize costs.
