defmodule ReqFly.Secrets do
  @moduledoc """
  Functions for interacting with Fly.io Secrets API.

  The Secrets API provides operations for managing application secrets, including
  listing, creating, generating, and destroying secrets.

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      # List all secrets for an app
      {:ok, secrets} = ReqFly.Secrets.list(req, app_name: "my-app")

      # Create a new secret
      {:ok, secret} = ReqFly.Secrets.create(req,
        app_name: "my-app",
        label: "DATABASE_URL",
        type: "env",
        value: "postgres://..."
      )

      # Generate a random secret
      {:ok, secret} = ReqFly.Secrets.generate(req,
        app_name: "my-app",
        label: "SECRET_KEY",
        type: "env"
      )

      # Destroy a secret
      {:ok, _} = ReqFly.Secrets.destroy(req,
        app_name: "my-app",
        label: "OLD_SECRET"
      )

  """

  @doc """
  Lists all secrets for an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)

  ## Returns

    * `{:ok, secrets}` - List of secret maps
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, secrets} = ReqFly.Secrets.list(req, app_name: "my-app")

  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, list(map())} | {:error, ReqFly.Error.t()}
  def list(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    validate_required!(app_name, :app_name)

    ReqFly.request(req, :get, "/apps/#{app_name}/secrets")
  end

  @doc """
  Creates a new secret for an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:label` - Secret label/name (required)
      * `:type` - Secret type, typically "env" (required)
      * `:value` - Secret value (required)

  ## Returns

    * `{:ok, secret}` - Created secret details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, secret} = ReqFly.Secrets.create(req,
        app_name: "my-app",
        label: "DATABASE_URL",
        type: "env",
        value: "postgres://..."
      )

  """
  @spec create(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def create(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    label = Keyword.get(opts, :label)
    type = Keyword.get(opts, :type)
    value = Keyword.get(opts, :value)

    validate_required!(app_name, :app_name)
    validate_required!(label, :label)
    validate_required!(type, :type)
    validate_required!(value, :value)

    json = %{
      label: label,
      type: type,
      value: value
    }

    ReqFly.request(req, :post, "/apps/#{app_name}/secrets", json: json)
  end

  @doc """
  Generates a random secret for an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:label` - Secret label/name (required)
      * `:type` - Secret type, typically "env" (required)

  ## Returns

    * `{:ok, secret}` - Generated secret details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, secret} = ReqFly.Secrets.generate(req,
        app_name: "my-app",
        label: "SECRET_KEY",
        type: "env"
      )

  """
  @spec generate(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def generate(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    label = Keyword.get(opts, :label)
    type = Keyword.get(opts, :type)

    validate_required!(app_name, :app_name)
    validate_required!(label, :label)
    validate_required!(type, :type)

    json = %{
      label: label,
      type: type
    }

    ReqFly.request(req, :post, "/apps/#{app_name}/secrets/generate", json: json)
  end

  @doc """
  Destroys (deletes) a secret from an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:label` - Secret label/name to destroy (required)

  ## Returns

    * `{:ok, response}` - Deletion confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Secrets.destroy(req,
        app_name: "my-app",
        label: "OLD_SECRET"
      )

  """
  @spec destroy(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def destroy(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    label = Keyword.get(opts, :label)

    validate_required!(app_name, :app_name)
    validate_required!(label, :label)

    ReqFly.request(req, :delete, "/apps/#{app_name}/secrets/#{label}")
  end

  # Private helpers

  defp validate_required!(value, _field_name) when is_binary(value) and byte_size(value) > 0 do
    :ok
  end

  defp validate_required!(value, field_name) when is_nil(value) or value == "" do
    raise ArgumentError, "#{field_name} is required"
  end

  defp validate_required!(_value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-empty string"
  end
end
