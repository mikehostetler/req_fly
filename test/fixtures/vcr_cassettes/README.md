# VCR Cassettes

This directory contains VCR cassettes for testing ReqFly integration with the Fly.io Machines API.

## What are VCR Cassettes?

VCR cassettes are recordings of HTTP interactions that can be replayed during tests. This allows tests to run without making actual HTTP requests to the Fly.io API, making them:

- **Faster**: No network latency
- **More reliable**: No dependency on external services
- **Reproducible**: Same response every time
- **Secure**: Authorization headers are filtered out

## Cassette Structure

Cassettes are JSON files with the following structure:

```json
[
  {
    "request": {
      "method": "get",
      "url": "https://api.machines.dev/v1/apps",
      "headers": {...},
      "body": ""
    },
    "response": {
      "status_code": 200,
      "headers": {...},
      "body": "{...}"
    }
  }
]
```

## Available Cassettes

### Apps

- **apps/list_personal.json**: List all apps for a personal organization
- **apps/get.json**: Get details for a specific app
- **apps/create.json**: Create a new app

## Using Cassettes in Tests

```elixir
defmodule MyTest do
  use ReqFly.FlyCase

  test "lists apps" do
    use_cassette "apps/list_personal" do
      req = build_req()
      {:ok, response} = Req.get(req, url: "/apps")
      
      assert response.status == 200
    end
  end
end
```

## Recording New Cassettes

To record new cassettes with actual API responses:

1. Set your Fly.io API token:
   ```bash
   export FLY_API_TOKEN="your_real_token_here"
   ```

2. Delete the existing cassette (if any)

3. Run the test - ExVCR will record the interaction

4. The cassette will be saved with Authorization headers filtered

## Security

**IMPORTANT**: Authorization headers are automatically filtered by ExVCR to prevent token leakage. The cassettes should contain `Bearer [FILTERED]` instead of actual tokens.

Always review new cassettes before committing to ensure no sensitive data is included.

## Alternative: Using Bypass

For many integration tests, using `Bypass` (a mock HTTP server) may be simpler than VCR cassettes. See `test/support/fly_case_test.exs` for examples of using Bypass with ReqFly.

Example:

```elixir
test "lists apps", %{bypass: bypass} do
  Bypass.expect_once(bypass, "GET", "/apps", fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, Jason.encode!(%{apps: []}))
  end)

  req = build_req(base_url: "http://localhost:#{bypass.port}")
  {:ok, response} = Req.get(req, url: "/apps")
  
  assert response.status == 200
end
```

## Maintenance

When the Fly.io API changes:

1. Delete affected cassettes
2. Record new ones with a real API token
3. Update tests if the response structure changed
4. Verify Authorization headers are still filtered
