defmodule ReqFly.Error do
  @moduledoc """
  Error struct and exception handling for ReqFly operations.

  This module defines the error structure used throughout ReqFly to represent
  failed HTTP requests and API errors from the Fly.io Machines API.

  ## Fields

    * `:status` - HTTP status code (e.g., 404, 500)
    * `:code` - Error code from the API response
    * `:reason` - Human-readable error message
    * `:request_id` - Fly request ID from the "fly-request-id" header
    * `:body` - Raw response body
    * `:method` - HTTP method used (e.g., "GET", "POST")
    * `:url` - Request URL

  ## Examples

      iex> error = %ReqFly.Error{status: 404, reason: "Machine not found"}
      iex> Exception.message(error)
      "[404] Machine not found"

  """

  defexception [
    :status,
    :code,
    :reason,
    :request_id,
    :body,
    :method,
    :url
  ]

  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          code: String.t() | nil,
          reason: String.t() | nil,
          request_id: String.t() | nil,
          body: any(),
          method: String.t() | nil,
          url: String.t() | nil
        }

  @doc """
  Returns a human-readable error message.

  ## Examples

      iex> error = %ReqFly.Error{status: 404, reason: "Not found"}
      iex> Exception.message(error)
      "[404] Not found"

      iex> error = %ReqFly.Error{reason: "Connection failed"}
      iex> Exception.message(error)
      "Connection failed"

  """
  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{status: status, reason: reason})
      when is_integer(status) and is_binary(reason) do
    "[#{status}] #{reason}"
  end

  def message(%__MODULE__{status: status, code: code})
      when is_integer(status) and is_binary(code) do
    "[#{status}] #{code}"
  end

  def message(%__MODULE__{reason: reason}) when is_binary(reason) do
    reason
  end

  def message(%__MODULE__{status: status}) when is_integer(status) do
    "HTTP #{status}"
  end

  def message(%__MODULE__{}) do
    "Unknown error"
  end

  @doc """
  Parses a Req.Response into a ReqFly.Error struct.

  Extracts error information from JSON responses with "error", "message", or "code" keys.
  Also extracts the "fly-request-id" header if present.

  ## Examples

      iex> response = %Req.Response{
      ...>   status: 404,
      ...>   body: %{"error" => "not_found", "message" => "Machine not found"},
      ...>   headers: %{"fly-request-id" => ["abc123"]}
      ...> }
      iex> ReqFly.Error.from_response(response)
      %ReqFly.Error{
        status: 404,
        code: "not_found",
        reason: "Machine not found",
        request_id: "abc123",
        body: %{"error" => "not_found", "message" => "Machine not found"}
      }

  """
  @spec from_response(Req.Response.t()) :: t()
  def from_response(%Req.Response{} = response) do
    request_id = extract_request_id(response)
    {code, reason} = extract_error_details(response.body)

    %__MODULE__{
      status: response.status,
      code: code,
      reason: reason,
      request_id: request_id,
      body: response.body,
      method: get_method(response),
      url: get_url(response)
    }
  end

  @spec from_response(Req.Response.t(), keyword()) :: t()
  def from_response(%Req.Response{} = response, opts) do
    error = from_response(response)

    %{error | method: opts[:method] || error.method, url: opts[:url] || error.url}
  end

  @doc """
  Creates an error from an exception or error tuple.

  ## Examples

      iex> ReqFly.Error.from_exception(%Mint.TransportError{reason: :timeout})
      %ReqFly.Error{reason: "timeout"}

  """
  @spec from_exception(Exception.t() | {:error, term()}) :: t()
  def from_exception(%_{} = exception) do
    %__MODULE__{
      reason: Exception.message(exception)
    }
  end

  def from_exception({:error, reason}) when is_atom(reason) do
    %__MODULE__{reason: to_string(reason)}
  end

  def from_exception({:error, reason}) when is_binary(reason) do
    %__MODULE__{reason: reason}
  end

  def from_exception({:error, reason}) do
    %__MODULE__{reason: inspect(reason)}
  end

  # Private functions

  defp extract_request_id(%Req.Response{headers: headers}) when is_map(headers) do
    # Try both key formats (string and atom keys, and check list values)
    headers
    |> Enum.find_value(fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == "fly-request-id" do
          case value do
            [request_id | _] -> request_id
            request_id when is_binary(request_id) -> request_id
            _ -> nil
          end
        end

      _ ->
        nil
    end)
  end

  defp extract_request_id(_), do: nil

  defp extract_error_details(body) when is_map(body) do
    code = body["error"] || body["code"]
    reason = body["message"] || body["error"] || body["reason"]

    {code, reason}
  end

  defp extract_error_details(body) when is_binary(body) do
    {nil, body}
  end

  defp extract_error_details(_), do: {nil, nil}

  defp get_method(%Req.Response{} = response) do
    case response do
      %{private: %{req_request: %{method: method}}} -> to_string(method) |> String.upcase()
      _ -> nil
    end
  end

  defp get_url(%Req.Response{} = response) do
    case response do
      %{private: %{req_request: %{url: %URI{} = uri}}} -> URI.to_string(uri)
      _ -> nil
    end
  end
end
