defmodule ReqFly.Volumes do
  @moduledoc """
  Functions for interacting with Fly.io Volumes API.

  The Volumes API provides operations for managing persistent storage volumes
  including creation, retrieval, updates, deletion, extension, and snapshot management.

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")

      # List all volumes for an app
      {:ok, volumes} = ReqFly.Volumes.list(req, app_name: "my-app")

      # Create a new volume
      {:ok, volume} = ReqFly.Volumes.create(req,
        app_name: "my-app",
        name: "data_volume",
        region: "sjc",
        size_gb: 10
      )

      # Get volume details
      {:ok, volume} = ReqFly.Volumes.get(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

      # Update a volume
      {:ok, volume} = ReqFly.Volumes.update(req,
        app_name: "my-app",
        volume_id: "vol_1234567890",
        snapshot_retention: 5
      )

      # Extend volume size
      {:ok, volume} = ReqFly.Volumes.extend(req,
        app_name: "my-app",
        volume_id: "vol_1234567890",
        size_gb: 20
      )

      # List snapshots
      {:ok, snapshots} = ReqFly.Volumes.list_snapshots(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

      # Create a snapshot
      {:ok, snapshot} = ReqFly.Volumes.create_snapshot(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

      # Delete a volume
      {:ok, _} = ReqFly.Volumes.delete(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

  """

  @doc """
  Lists all volumes for an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)

  ## Returns

    * `{:ok, volumes}` - List of volume maps
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, volumes} = ReqFly.Volumes.list(req, app_name: "my-app")

  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, list(map())} | {:error, ReqFly.Error.t()}
  def list(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    validate_required!(app_name, :app_name)

    ReqFly.request(req, :get, "/apps/#{app_name}/volumes")
  end

  @doc """
  Creates a new volume for an app.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:name` - Volume name (required)
      * `:region` - Region code (e.g., "sjc", "iad") (required)
      * `:size_gb` - Size in gigabytes (required, must be positive integer)
      * Additional optional parameters can be passed and will be included in the request

  ## Returns

    * `{:ok, volume}` - Created volume details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, volume} = ReqFly.Volumes.create(req,
        app_name: "my-app",
        name: "data_volume",
        region: "sjc",
        size_gb: 10
      )

  """
  @spec create(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def create(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    name = Keyword.get(opts, :name)
    region = Keyword.get(opts, :region)
    size_gb = Keyword.get(opts, :size_gb)

    validate_required!(app_name, :app_name)
    validate_required!(name, :name)
    validate_required!(region, :region)
    validate_positive_integer!(size_gb, :size_gb)

    # Build json with all provided opts except app_name
    json =
      opts
      |> Keyword.delete(:app_name)
      |> Enum.into(%{})

    ReqFly.request(req, :post, "/apps/#{app_name}/volumes", json: json)
  end

  @doc """
  Gets details for a specific volume.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:volume_id` - ID of the volume (required)

  ## Returns

    * `{:ok, volume}` - Volume details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, volume} = ReqFly.Volumes.get(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

  """
  @spec get(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def get(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    volume_id = Keyword.get(opts, :volume_id)

    validate_required!(app_name, :app_name)
    validate_required!(volume_id, :volume_id)

    ReqFly.request(req, :get, "/apps/#{app_name}/volumes/#{volume_id}")
  end

  @doc """
  Updates a volume's configuration.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:volume_id` - ID of the volume (required)
      * Additional parameters to update (e.g., `:snapshot_retention`)

  ## Returns

    * `{:ok, volume}` - Updated volume details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, volume} = ReqFly.Volumes.update(req,
        app_name: "my-app",
        volume_id: "vol_1234567890",
        snapshot_retention: 5
      )

  """
  @spec update(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def update(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    volume_id = Keyword.get(opts, :volume_id)

    validate_required!(app_name, :app_name)
    validate_required!(volume_id, :volume_id)

    # Build json with all provided opts except app_name and volume_id
    json =
      opts
      |> Keyword.delete(:app_name)
      |> Keyword.delete(:volume_id)
      |> Enum.into(%{})

    ReqFly.request(req, :post, "/apps/#{app_name}/volumes/#{volume_id}", json: json)
  end

  @doc """
  Deletes a volume.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:volume_id` - ID of the volume to delete (required)

  ## Returns

    * `{:ok, response}` - Deletion confirmation
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, _} = ReqFly.Volumes.delete(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

  """
  @spec delete(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, ReqFly.Error.t()}
  def delete(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    volume_id = Keyword.get(opts, :volume_id)

    validate_required!(app_name, :app_name)
    validate_required!(volume_id, :volume_id)

    ReqFly.request(req, :delete, "/apps/#{app_name}/volumes/#{volume_id}")
  end

  @doc """
  Extends the size of a volume.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:volume_id` - ID of the volume (required)
      * `:size_gb` - New size in gigabytes (required, must be positive integer)

  ## Returns

    * `{:ok, volume}` - Extended volume details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, volume} = ReqFly.Volumes.extend(req,
        app_name: "my-app",
        volume_id: "vol_1234567890",
        size_gb: 20
      )

  """
  @spec extend(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def extend(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    volume_id = Keyword.get(opts, :volume_id)
    size_gb = Keyword.get(opts, :size_gb)

    validate_required!(app_name, :app_name)
    validate_required!(volume_id, :volume_id)
    validate_positive_integer!(size_gb, :size_gb)

    json = %{size_gb: size_gb}

    ReqFly.request(req, :post, "/apps/#{app_name}/volumes/#{volume_id}/extend", json: json)
  end

  @doc """
  Lists all snapshots for a volume.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:volume_id` - ID of the volume (required)

  ## Returns

    * `{:ok, snapshots}` - List of snapshot maps
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, snapshots} = ReqFly.Volumes.list_snapshots(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

  """
  @spec list_snapshots(Req.Request.t(), keyword()) ::
          {:ok, list(map())} | {:error, ReqFly.Error.t()}
  def list_snapshots(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    volume_id = Keyword.get(opts, :volume_id)

    validate_required!(app_name, :app_name)
    validate_required!(volume_id, :volume_id)

    ReqFly.request(req, :get, "/apps/#{app_name}/volumes/#{volume_id}/snapshots")
  end

  @doc """
  Creates a snapshot of a volume.

  ## Parameters

    * `req` - A Req.Request with ReqFly attached
    * `opts` - Options keyword list
      * `:app_name` - Name of the app (required)
      * `:volume_id` - ID of the volume (required)

  ## Returns

    * `{:ok, snapshot}` - Created snapshot details
    * `{:error, %ReqFly.Error{}}` - Error details

  ## Examples

      req = Req.new() |> ReqFly.attach(token: "fly_token")
      {:ok, snapshot} = ReqFly.Volumes.create_snapshot(req,
        app_name: "my-app",
        volume_id: "vol_1234567890"
      )

  """
  @spec create_snapshot(Req.Request.t(), keyword()) :: {:ok, map()} | {:error, ReqFly.Error.t()}
  def create_snapshot(req, opts) do
    app_name = Keyword.get(opts, :app_name)
    volume_id = Keyword.get(opts, :volume_id)

    validate_required!(app_name, :app_name)
    validate_required!(volume_id, :volume_id)

    ReqFly.request(req, :post, "/apps/#{app_name}/volumes/#{volume_id}/snapshots", json: %{})
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

  defp validate_positive_integer!(value, _field_name) when is_integer(value) and value > 0 do
    :ok
  end

  defp validate_positive_integer!(value, field_name) when is_nil(value) do
    raise ArgumentError, "#{field_name} is required"
  end

  defp validate_positive_integer!(_value, field_name) do
    raise ArgumentError, "#{field_name} must be a positive integer"
  end
end
