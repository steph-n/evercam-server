defmodule EvercamMedia.Snapshot.UpdateThumbnail do
  @moduledoc """
  Provides functions and workers for update camera thumbnail

  """

  use GenStage
  require Logger
  import EvercamMedia.Snapshot.Storage, only: [check_camera_last_image: 1]

  ################
  ## Client API ##
  ################

  @doc """
  Start a worker for camera thumbnail update.
  """
  def start_link(args) do
    GenStage.start_link(__MODULE__, args)
  end

  @doc """
  Get the configuration of the camera thumbnail update.
  """
  def get_config(cam_server) do
    GenStage.call(cam_server, :get_thumbnail_update_config)
  end

  @doc """
  Update the configuration of the camera worker
  """
  def update_config(cam_server, config) do
    GenStage.cast(cam_server, {:update_camera_config, config})
  end


  ######################
  ## Server Callbacks ##
  ######################

  @doc """
  Initialize the camera thumbnail server
  """
  def init(args) do
    args = Map.merge args, %{
      timer: start_timer(:thumbnail_update)
    }
    {:consumer, args}
  end

  def handle_cast({:update_camera_config, new_config}, state) do
    {:ok, timer} = Map.fetch(state, :timer)
    :erlang.cancel_timer(timer)
    new_timer = start_timer(:thumbnail_update)
    new_config = Map.merge new_config, %{
      timer: new_timer
    }
    {:noreply, [], new_config}
  end

  @doc """
  Server callback for getting camera thumbnail state
  """
  def handle_call(:get_thumbnail_update_config, _from, state) do
    {:reply, state, [], state}
  end

  @doc """
  Server callback for update thumbnail
  """
  def handle_info(:thumbnail_update, state) do
    {:ok, timer} = Map.fetch(state, :timer)
    :erlang.cancel_timer(timer)
    camera = Camera.get(state.config.camera_exid)

    case {camera.is_online, state.config.recording} do
      {true, "on"} -> Logger.debug "Camera recording process is running, Don't update thumbnail."
      _ -> check_camera_last_image(state.config.camera_exid)
    end

    timer = start_timer(:thumbnail_update)
    {:noreply, [], Map.put(state, :timer, timer)}
  end

  @doc """
  Take care of unknown messages which otherwise would trigger function clause mismatch error.
  """
  def handle_info(msg, state) do
    Logger.info "[handle_info] [#{msg}] [#{state.name}] [unknown messages]"
    {:noreply, [], state}
  end

  #######################
  ## Private functions ##
  #######################

  defp start_timer(message) do
    Process.send_after(self(), message, 1000 * 60 * 30)
  end
end
