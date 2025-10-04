defmodule ReqFly.FlyCase do
  @moduledoc """
  Test case template for Fly.io API integration tests.

  This module provides a comprehensive test environment for testing ReqFly
  functionality with ExVCR cassettes for recording and replaying HTTP interactions.

  ## Features

  - ExVCR integration with pre-configured cassette directory
  - Helper for building configured Req clients
  - Telemetry event capturing and assertion
  - Automatic Authorization header filtering for security
  - Common test utilities and imports

  ## Usage

      defmodule MyTest do
        use ReqFly.FlyCase

        test "lists apps" do
          use_cassette "apps/list_personal" do
            req = build_req()
            {:ok, apps} = ReqFly.Apps.list(req)
            assert is_list(apps)
          end
        end

        test "captures telemetry events" do
          events = capture_telemetry_events([:req_fly, :request, :stop], fn ->
            req = build_req()
            Req.get!(req, url: "/apps")
          end)

          assert_telemetry_event(events, [:req_fly, :request, :stop], %{
            method: :get
          })
        end
      end

  ## Environment Variables

  - `FLY_API_TOKEN` - Real Fly.io API token (used when recording new cassettes)

  When recording new cassettes, set FLY_API_TOKEN to your real token. When
  running tests with existing cassettes, the token is not required as requests
  are replayed from recordings.

  ## Cassette Directory

  Cassettes are stored in `test/fixtures/vcr_cassettes/`. The Authorization
  header is automatically filtered to prevent token leakage.

  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

      import ReqFly.FlyCase
    end
  end

  @doc """
  Builds a configured Req client with ReqFly attached.

  Reads the Fly.io API token from the `FLY_API_TOKEN` environment variable,
  or uses a dummy token for testing with recorded cassettes.

  ## Options

    * `:token` - Override the default token
    * All other options are passed to `ReqFly.attach/2`

  ## Examples

      req = build_req()
      {:ok, apps} = ReqFly.Apps.list(req)

      # With custom token
      req = build_req(token: "custom_token")

      # With custom base_url
      req = build_req(base_url: "https://api.machines.dev/v1")

  """
  @spec build_req(keyword()) :: Req.Request.t()
  def build_req(opts \\ []) do
    token = opts[:token] || System.get_env("FLY_API_TOKEN") || "dummy_token_for_tests"
    opts = Keyword.put(opts, :token, token)

    Req.new(finch: ReqFlyFinch)
    |> ReqFly.attach(opts)
  end

  @doc """
  Captures telemetry events emitted during function execution.

  Attaches a telemetry handler for the specified event, executes the function,
  and returns a list of all events that were emitted.

  ## Parameters

    * `event_name` - Telemetry event name (list of atoms)
    * `fun` - Function to execute while capturing events

  ## Returns

  List of tuples: `{event_name, measurements, metadata}`

  ## Examples

      events = capture_telemetry_events([:req_fly, :request, :stop], fn ->
        req = build_req()
        Req.get!(req, url: "/apps")
      end)

      assert length(events) > 0

      # Capture multiple event types
      events = capture_telemetry_events([:req_fly, :request], fn ->
        req = build_req()
        Req.get!(req, url: "/apps")
      end)

      # Events will include [:req_fly, :request, :start] and
      # [:req_fly, :request, :stop]

  """
  @spec capture_telemetry_events([atom()], (-> any())) :: [
          {[atom()], map(), map()}
        ]
  def capture_telemetry_events(event_prefix, fun) do
    parent = self()
    ref = make_ref()

    # Attach handler for all events matching prefix
    handler_id = {:req_fly_test_handler, ref}

    :telemetry.attach_many(
      handler_id,
      [event_prefix ++ [:start], event_prefix ++ [:stop], event_prefix ++ [:exception]],
      fn event_name, measurements, metadata, _config ->
        send(parent, {ref, event_name, measurements, metadata})
      end,
      nil
    )

    # Execute function
    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    # Collect all events
    collect_events(ref, [])
  end

  @doc """
  Asserts that a specific telemetry event was emitted.

  Searches through captured events and asserts that at least one event
  matches the expected name and metadata.

  ## Parameters

    * `events` - List of events from `capture_telemetry_events/2`
    * `event_name` - Expected event name (list of atoms)
    * `expected_metadata` - Map of metadata to match (subset matching)

  ## Examples

      events = capture_telemetry_events([:req_fly, :request], fn ->
        req = build_req()
        Req.get!(req, url: "/apps")
      end)

      assert_telemetry_event(events, [:req_fly, :request, :stop], %{
        method: :get,
        status: 200
      })

      # Partial metadata matching
      assert_telemetry_event(events, [:req_fly, :request, :start], %{
        method: :get
      })

  """
  @spec assert_telemetry_event([{[atom()], map(), map()}], [atom()], map()) :: true
  def assert_telemetry_event(events, event_name, expected_metadata) do
    matching_event =
      Enum.find(events, fn {name, _measurements, metadata} ->
        name == event_name && metadata_matches?(metadata, expected_metadata)
      end)

    if matching_event do
      true
    else
      flunk("""
      Expected telemetry event not found.

      Event name: #{inspect(event_name)}
      Expected metadata (subset): #{inspect(expected_metadata)}

      Captured events:
      #{format_events(events)}
      """)
    end
  end

  # Private helpers

  defp collect_events(ref, acc) do
    receive do
      {^ref, event_name, measurements, metadata} ->
        collect_events(ref, [{event_name, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp metadata_matches?(metadata, expected) do
    Enum.all?(expected, fn {key, value} ->
      Map.get(metadata, key) == value
    end)
  end

  defp format_events(events) do
    Enum.map_join(events, "\n\n", fn {name, measurements, metadata} ->
      "  - #{inspect(name)}\n    Measurements: #{inspect(measurements)}\n    Metadata: #{inspect(metadata)}"
    end)
  end

  # Import ExUnit assertions
  import ExUnit.Assertions, only: [flunk: 1]
end
