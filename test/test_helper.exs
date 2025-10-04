# Start Finch for HTTP requests
{:ok, _} = Finch.start_link(name: ReqFlyFinch)

# Exclude integration tests by default (run with --only integration or --include integration)
ExUnit.start(exclude: [integration: true], capture_log: true)

# ExVCR Configuration
ExVCR.Config.cassette_library_dir("test/fixtures/vcr_cassettes")
ExVCR.Config.filter_sensitive_data("Bearer .+", "Bearer [FILTERED]")
ExVCR.Config.filter_url_params(true)
ExVCR.Config.filter_request_headers(["authorization"])
ExVCR.Config.response_headers_blacklist(["set-cookie", "x-request-id"])
