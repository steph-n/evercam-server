defmodule EvercamMedia.Snapshot.Worker do
  @moduledoc """
  Provides functions and workers for getting snapshots from the camera

  Functions can be called from other places to get snapshots manually.
  """

  use GenStage
  alias EvercamMedia.Snapshot.CamClient

  import EvercamMedia.Util, only: [camera_use_synchronous_req: 1]

  ################
  ## Client API ##
  ################

  @doc """
  Start the Snapshot server for a given camera.
  """
  def start_link(args) do
    GenStage.start_link(__MODULE__, args, name: args[:name])
  end

  @doc """
  Restart the poller for the camera that takes snapshot in frequent interval
  as defined in the args passed to the camera server.
  """
  def start_poller(cam_server) do
    GenStage.call(cam_server, :restart_camera_poller)
  end

  @doc """
  Stop the poller for the camera.
  """
  def stop_poller(cam_server) do
    GenStage.call(cam_server, :stop_camera_poller)
  end

  @doc """
  Get the state of the camera worker.
  """
  def get_state(cam_server) do
    GenStage.call(cam_server, :get_state)
  end

  @doc """
  Get the configuration of the camera worker.
  """
  def get_config(cam_server) do
    GenStage.call(cam_server, :get_camera_config)
  end

  @doc """
  Update the configuration of the camera worker
  """
  def update_config(cam_server, config) do
    GenStage.cast(cam_server, {:update_camera_config, config})
  end

  @doc """
  Get a snapshot from the camera server
  """
  def get_snapshot(cam_server, {:poll, timestamp}) do
    GenStage.cast(cam_server, {:get_camera_snapshot, timestamp})
  end
  def get_snapshot(cam_server, reply_to) do
    timestamp = Calendar.DateTime.Format.unix(Calendar.DateTime.now_utc)
    GenStage.cast(cam_server, {:get_camera_snapshot, timestamp, reply_to})
  end

  ######################
  ## Server Callbacks ##
  ######################

  @doc """
  Initialize the camera server
  """
  def init(args) do
    {:ok, storage_manager} = GenStage.start_link(EvercamMedia.Snapshot.StorageHandler, :ok)
    {:ok, snapshot_manager} = GenStage.start_link(EvercamMedia.Snapshot.DBHandler, :ok)
    {:ok, poll_manager} = GenStage.start_link(EvercamMedia.Snapshot.PollHandler, :ok)
    args = Map.merge args, %{
      storage_manager: storage_manager,
      snapshot_manager: snapshot_manager,
      poll_manager: poll_manager
    }

    {:ok, poller} = EvercamMedia.Snapshot.Poller.start_link(args)
    {:ok, update_thumbnail} = EvercamMedia.Snapshot.UpdateThumbnail.start_link(args)
    args = Map.merge(args, %{ poller: poller, update_thumbnail: update_thumbnail })
    config = Map.get(args, :config)

    args = case config.recording do
      "off" -> args
      _ ->
        {:ok, deletion} = EvercamMedia.Snapshot.Deletion.start_link(args)
        Map.merge(args, %{ deletion: deletion })
    end

    {:producer, args}
  end

  @doc """
  Server callback for restarting camera poller
  """
  def handle_call(:restart_camera_poller, _from, state) do
    {:reply, nil, [], state}
  end

  @doc """
  Server callback for stopping camera poller
  """
  def handle_call(:stop_camera_poller, _from, state) do
    {:reply, nil, [], state}
  end

  @doc """
  Server callback for getting camera config
  """
  def handle_call(:get_camera_config, _from, state) do
    {:reply, get_config_from_state(:config, state), [], state}
  end

  @doc """
  Server callback for getting worker state
  """
  def handle_call(:get_state, _from, state) do
    {:reply, state, [], state}
  end

  @doc """
  Server callback for getting snapshot
  """
  def handle_cast({:get_camera_snapshot, timestamp, reply_to}, state) do
    _get_snapshot(state, timestamp, reply_to)
    {:noreply, [], state}
  end

  @doc """
  """
  def handle_cast({:get_camera_snapshot, timestamp}, state) do
    _get_snapshot(state, timestamp)
    {:noreply, [], state}
  end

  @doc """
  Server callback for updating camera config
  """
  def handle_cast({:update_camera_config, config}, state) do
    updated_config = Map.merge state, config
    GenStage.sync_info(state.poll_manager, {:update_camera_config, updated_config})
    {:noreply, [], updated_config}
  end

  @doc """
  Server callback for camera_reply
  """
  def handle_info({:camera_reply, result, timestamp, reply_to}, state) do
    ConCache.put(:do_camera_request, state.config.camera_exid, true)
    case result do
      {:ok, image} ->
        data = {state.name, timestamp, image}
        GenStage.sync_info(state.snapshot_manager, {:got_snapshot, data})
      {:error, error} ->
        data = {state.name, timestamp, error}
        GenStage.sync_info(state.snapshot_manager, {:snapshot_error, data})
    end
    if is_pid(reply_to) do
      send reply_to, result
    end
    {:noreply, [], state}
  end

  @doc """
  Take care of unknown messages which otherwise would trigger function clause mismatch error.
  """
  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  #####################
  # Private functions #
  #####################

  defp get_config_from_state(:config, state) do
    Map.get(state, :config)
  end

  defp _get_snapshot(state, timestamp, reply_to \\ nil) do
    config = get_config_from_state(:config, state)
    camera_exid = config.camera_exid
    worker = self()
    try_snapshot(state, config, camera_exid, timestamp, reply_to, worker, 1)
  end

  defp try_snapshot(_state, config, camera_exid, old_timestamp, reply_to, worker, 3) do
    spawn fn ->
      new_timestamp = Calendar.DateTime.Format.unix(Calendar.DateTime.now_utc)
      result =
        config
        |> add_missing_params(new_timestamp, 3)
        |> CamClient.fetch_snapshot
      ConCache.delete(:camera_lock, camera_exid)
      timestamp =
        case result do
          {:error, _error} -> old_timestamp
          _ -> new_timestamp
        end
      ConCache.put(:do_camera_request, camera_exid, true)
      send worker, {:camera_reply, result, timestamp, reply_to}
    end
  end

  defp try_snapshot(state, config, camera_exid, timestamp, reply_to, worker, attempt) do
    camera = Camera.get(camera_exid)
    spawn fn ->
      ConCache.put(:do_camera_request, camera_exid, false)
      result =
        config
        |> add_missing_params(timestamp, attempt)
        |> CamClient.fetch_snapshot

      case {result, camera.status} do
        {{:error, _error}, "online"} ->
          if ConCache.get(:camera_lock, state.config.camera_exid) && attempt == 1 do
            ConCache.put(:do_camera_request, camera_exid, true)
            Process.exit self(), :shutdown
          end
          ConCache.put(:camera_lock, camera_exid, camera_exid)

          case camera_use_synchronous_req(camera_exid) do
            true -> 600
            _ -> 0
          end
          |> :timer.sleep

          try_snapshot(state, config, camera_exid, timestamp, reply_to, worker, attempt + 1)
        _ ->
          ConCache.delete(:camera_lock, camera_exid)
          ConCache.put(:do_camera_request, camera_exid, true)
          send worker, {:camera_reply, result, timestamp, reply_to}
      end
    end
  end

  defp add_missing_params(config, timestamp, attempt) do
    config
    |> Map.put(:timestamp, timestamp)
    |> Map.put(:description, "Recordings attempt #{attempt}")
  end
end
