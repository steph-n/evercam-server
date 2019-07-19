defmodule EvercamMedia.Snapshot.StorageHandler do
  @moduledoc """
  TODO
  """

  use GenStage
  alias EvercamMedia.Snapshot.Storage
  require Logger

  def init(:ok) do
    {:producer_consumer, :ok}
  end

  def handle_info({:save_snapshot, data}, state) do
    {camera_exid, timestamp, image} = data
    spawn fn -> Storage.seaweedfs_save(camera_exid, timestamp, image, "Evercam Proxy") end
    {:noreply, [], state}
  end

  def handle_info(_, state) do
    {:noreply, [], state}
  end
end
