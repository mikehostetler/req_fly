defmodule ReqFly.Steps do
  @moduledoc """
  Custom Req pipeline steps for Fly.io API integration.

  This module provides request and response processing steps that integrate
  with the Req HTTP client pipeline to handle Fly.io-specific requirements
  like authentication, error handling, and telemetry.

  ## Pipeline Steps

    * `attach_auth/1` - Adds Authorization header with Bearer token
    * `attach_base_url/1` - Sets the base URL for Fly.io API
    * `attach_headers/1` - Adds required headers (User-Agent, Accept)
    * `handle_error_response/1` - Converts non-2xx responses to ReqFly.Error
    * `attach_telemetry/1` - Emits telemetry events for observability

  """

  @doc """
  Attaches the Authorization Bearer header to the request.

  Reads the token from the `:fly_token` option on the request.

  ## Examples

      iex> request = %Req.Request{options: %{fly_token: "secret"}}
      iex> request = ReqFly.Steps.attach_auth(request)
      iex> request.headers["authorization"]
      ["Bearer secret"]

  """
  @spec attach_auth(Req.Request.t()) :: Req.Request.t()
  def attach_auth(%Req.Request{} = request) do
    case request.options[:fly_token] do
      nil ->
        request

      token ->
        Req.Request.put_header(request, "authorization", "Bearer #{token}")
    end
  end

  @doc """
  Attaches the base URL to the request from the `:fly_base_url` option.

  ## Examples

      iex> request = %Req.Request{options: %{fly_base_url: "https://api.machines.dev/v1"}}
      iex> request = ReqFly.Steps.attach_base_url(request)
      iex> request.options.base_url
      "https://api.machines.dev/v1"

  """
  @spec attach_base_url(Req.Request.t()) :: Req.Request.t()
  def attach_base_url(%Req.Request{} = request) do
    case request.options[:fly_base_url] do
      nil ->
        request

      base_url ->
        Req.Request.merge_options(request, base_url: base_url)
    end
  end

  @doc """
  Attaches standard headers required for Fly.io API requests.

  Adds:
  - User-Agent: "req_fly/0.1.0 (+Req)"
  - Accept: "application/json"

  ## Examples

      iex> request = %Req.Request{}
      iex> request = ReqFly.Steps.attach_headers(request)
      iex> request.headers["user-agent"]
      ["req_fly/0.1.0 (+Req)"]

  """
  @spec attach_headers(Req.Request.t()) :: Req.Request.t()
  def attach_headers(%Req.Request{} = request) do
    request
    |> Req.Request.put_header("user-agent", "req_fly/0.1.0 (+Req)")
    |> Req.Request.put_header("accept", "application/json")
  end

  @doc """
  Handles error responses by converting non-2xx responses to ReqFly.Error.

  ## Examples

      iex> response = %Req.Response{status: 404, body: %{"error" => "not_found"}}
      iex> {:error, error} = ReqFly.Steps.handle_error_response({:ok, response})
      iex> error.status
      404

  """
  @spec handle_error_response({:ok, Req.Response.t()} | {:error, Exception.t()}) ::
          {:ok, Req.Response.t()} | {:error, ReqFly.Error.t()}
  def handle_error_response({:ok, %Req.Response{status: status} = response})
      when status >= 200 and status < 300 do
    {:ok, response}
  end

  def handle_error_response({:ok, %Req.Response{} = response}) do
    {:error, ReqFly.Error.from_response(response)}
  end

  def handle_error_response({:error, exception}) do
    {:error, ReqFly.Error.from_exception(exception)}
  end

  @doc """
  Attaches telemetry to emit events during request lifecycle.

  Emits the following telemetry events:
  - `[:req_fly, :request, :start]` - When request starts
  - `[:req_fly, :request, :stop]` - When request completes successfully
  - `[:req_fly, :request, :exception]` - When request fails

  The telemetry prefix can be customized using the `:fly_telemetry_prefix` option.

  ## Examples

      iex> request = %Req.Request{options: %{fly_telemetry_prefix: [:my_app, :fly]}}
      iex> request = ReqFly.Steps.attach_telemetry(request)

  """
  @spec attach_telemetry(Req.Request.t()) :: Req.Request.t()
  def attach_telemetry(%Req.Request{} = request) do
    prefix = request.options[:fly_telemetry_prefix] || [:req_fly]

    request
    |> Req.Request.prepend_request_steps([
      {:req_fly_telemetry_start, &telemetry_start(&1, prefix)}
    ])
    |> Req.Request.append_response_steps([
      {:req_fly_telemetry_stop, &telemetry_stop(&1, prefix)}
    ])
    |> Req.Request.append_error_steps([
      {:req_fly_telemetry_exception, &telemetry_exception(&1, prefix)}
    ])
  end

  # Private telemetry functions

  defp telemetry_start(request, prefix) do
    start_time = System.monotonic_time()
    metadata = build_metadata(request)

    :telemetry.execute(
      prefix ++ [:request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    Req.Request.put_private(request, :req_fly_telemetry_start_time, start_time)
  end

  defp telemetry_stop({request, response_or_error}, prefix) do
    case Req.Request.get_private(request, :req_fly_telemetry_start_time) do
      nil ->
        {request, response_or_error}

      start_time ->
        duration = System.monotonic_time() - start_time
        metadata = build_metadata(request, response_or_error)

        :telemetry.execute(
          prefix ++ [:request, :stop],
          %{duration: duration},
          metadata
        )

        {request, response_or_error}
    end
  end

  defp telemetry_exception({request, exception}, prefix) do
    case Req.Request.get_private(request, :req_fly_telemetry_start_time) do
      nil ->
        {request, exception}

      start_time ->
        duration = System.monotonic_time() - start_time
        metadata = build_metadata(request, exception)

        :telemetry.execute(
          prefix ++ [:request, :exception],
          %{duration: duration},
          metadata
        )

        {request, exception}
    end
  end

  defp build_metadata(request, response_or_error \\ nil) do
    base_metadata = %{
      method: request.method,
      url: request.url && URI.to_string(request.url)
    }

    case response_or_error do
      %Req.Response{status: status} ->
        Map.put(base_metadata, :status, status)

      %{__exception__: true} = exception ->
        Map.put(base_metadata, :error, Exception.message(exception))

      _ ->
        base_metadata
    end
  end
end
