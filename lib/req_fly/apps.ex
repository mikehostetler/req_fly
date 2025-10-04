defmodule ReqFly.Apps do
  @moduledoc """
  Functions for interacting with Fly.io Apps API.

  The Apps API provides operations for managing Fly.io applications including
  listing, creating, retrieving, and destroying apps.

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      # List all apps in an organization
      {:ok, apps} = ReqFly.Apps.list(req, org_slug: "my-org")

      # Create a new app
      {:ok, app} = ReqFly.Apps.create(req, app_name: "my-app", org_slug: "my-org")

      # Get app details
      {:ok, app} = ReqFly.Apps.get(req, "my-app")

      # Destroy an app
      {:ok, _} = ReqFly.Apps.destroy(req, "my-app")

  """

  @doc """
  Lists all apps, optionally filtered by organization.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:org_slug` - Filter apps by organization slug (optional)

  ## Returns

    * `{:ok, apps}` - List of app maps
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      # List all apps
      {:ok, apps} = ReqFly.Apps.list(req)

      # List apps in a specific organization
      {:ok, apps} = ReqFly.Apps.list(req, org_slug: "my-org")

  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, list(map())} | {:error, ReqFly.Error.t()}
  def list(req, opts \\ []) do
    params =
      case Keyword.get(opts, :org_slug) do
        nil -> []
        org_slug -> [org_slug: org_slug]
      end

    ReqFly.request(req, :get, "/apps", params: params)
  end

  @doc """
  Creates a new Fly.io application.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list (required)
      * `:app_name` - Name of the app to create (required)
      * `:org_slug` - Organization slug (required)

  ## Returns

    * `{:ok, app}` - Created app details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, app} = ReqFly.Apps.create(req, app_name: "my-app", org_slug: "my-org")

  """
  @spec create(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def create(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    org_slug = Keyword.get(opts, :org_slug)

    validate_required!(app_name, :app_name)
    validate_required!(org_slug, :org_slug)

    json = %{
      app_name: app_name,
      org_slug: org_slug
    }

    ReqFly.request(req, :post, "/apps", json: json)
  end

  @doc """
  Gets details for a specific app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `app_name` - Name of the app to retrieve

  ## Returns

    * `{:ok, app}` - App details
    * `{:error, %ReqFly.Error{}}` - Error details (e.g., 404 if not found)

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, app} = ReqFly.Apps.get(req, "my-app")

  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def get(req, app_name) do
    validate_required!(app_name, :app_name)
    ReqFly.request(req, :get, "/apps/#{app_name}")
  end

  @doc """
  Destroys (deletes) a Fly.io application.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `app_name` - Name of the app to destroy

  ## Returns

    * `{:ok, response}` - Deletion confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Apps.destroy(req, "my-app")

  """
  @spec destroy(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def destroy(req, app_name) do
    validate_required!(app_name, :app_name)
    ReqFly.request(req, :delete, "/apps/#{app_name}")
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
