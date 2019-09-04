defmodule EvercamMedia.Snapshot.Streamer do
  @moduledoc """
  TODO
  """

  use GenStage
  alias EvercamMedia.Util
  alias EvercamMedia.Snapshot.CamClient
  alias EvercamMedia.Snapshot.DBHandler
  alias EvercamMedia.Snapshot.Error
  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.Snapshot.StreamerSupervisor
  require Logger

  @dunkettle_cameras Application.get_env(:evercam_media, :dunkettle_cameras) |> String.split(",")

  ################
  ## Client API ##
  ################

  @doc """
  Start the Snapshot streamer for a given camera.
  """
  def start_link(camera_exid) do
    streamer_id = String.to_atom("#{camera_exid}_streamer")
    GenStage.start_link(__MODULE__, camera_exid, name: streamer_id)
  end

  ######################
  ## Server Callbacks ##
  ######################

  @doc """
  Initialize the camera streamer
  """
  def init(camera_exid) do
    Process.send_after(self(), :tick, 0)
    {:producer, camera_exid}
  end

  @doc """
  Either stream a snapshot to subscribers or shut down streaming
  """
  def handle_info(:tick, nil), do: :noop
  def handle_info(:tick, camera_exid) do
    camera = Camera.get_full(camera_exid)
    cond do
      camera == nil ->
        Logger.debug "[#{camera_exid}] Shutting down streamer, camera doesn't exist"
        ConCache.put(:do_camera_request, camera.exid, true)
        StreamerSupervisor.stop_streamer(camera_exid)
      length(subscribers(camera_exid)) == 0 ->
        Logger.debug "[#{camera_exid}] Shutting down streamer, no subscribers"
        ConCache.put(:do_camera_request, camera.exid, true)
        StreamerSupervisor.stop_streamer(camera_exid)
      Util.camera_recording?(camera) ->
        Logger.debug "[#{camera_exid}] Shutting down streamer, already streaming"
        ConCache.put(:do_camera_request, camera.exid, true)
        StreamerSupervisor.stop_streamer(camera_exid)
      true ->
        Logger.debug "[#{camera_exid}] Streaming ..."
        spawn fn ->
          is_synchronous = Util.camera_use_synchronous_req(camera_exid)
          case {is_synchronous, ConCache.get(:do_camera_request, camera_exid)} do
            {true, false} -> Logger.debug "Streaming: Don't send snapshot request to camera #{camera.name}"
            _ -> stream(camera)
          end
        end
    end
    Process.send_after(self(), :tick, get_fps(camera_exid))
    {:noreply, [], camera_exid}
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

  def stream(camera) do
    ConCache.put(:do_camera_request, camera.exid, false)
    timestamp = Calendar.DateTime.now_utc |> Calendar.DateTime.Format.unix
    response = camera |> construct_args(timestamp) |> CamClient.fetch_snapshot
    ConCache.put(:do_camera_request, camera.exid, true)

    case response do
      {:ok, data} ->
        Util.broadcast_snapshot(camera.exid, data, timestamp)
        DBHandler.update_camera_status(camera.exid, timestamp, "online")
        spawn fn -> Storage.update_cache_thumbnail("#{camera.exid}", timestamp, data) end
      {:error, error} ->
        Error.parse(error) |> Error.handle(camera.exid, timestamp, error)
    end
  end

  def subscribers(camera_exid) do
    Phoenix.PubSub.Local.subscribers(EvercamMedia.PubSub, "cameras:#{camera_exid}", 0)
  end

  def parse_clients(camera_exid) do
    pids = Phoenix.PubSub.Local.subscribers(EvercamMedia.PubSub, "cameras:#{camera_exid}", 0)
    Enum.map(pids, fn(pid) ->
      socket = Phoenix.Channel.Server.socket(pid)
      case socket do
        %Phoenix.Socket{assigns: %{current_user: user, ip: ip, source: source}} ->
          desc =
            "#{user.username}"
            |> check_empty_nil(ip)
            |> check_empty_nil(source)
          "{#{desc}}"
        %Phoenix.Socket{assigns: %{ip: ip, source: source}} -> "{#{ip}, #{source}}"
        _ -> ""
      end
    end)
    |> Enum.filter(fn(v) -> v != "" end)
    |> Enum.join(", ")
  end

  defp get_fps(camera_exid) when camera_exid in @dunkettle_cameras, do: 2000
  defp get_fps(_), do: 1000

  defp check_empty_nil(desc, value) when value in [nil, ""], do: desc
  defp check_empty_nil(desc, value), do: "#{desc}, #{value}"

  defp construct_args(camera, timestamp) do
    %{
      camera_exid: camera.exid,
      description: "Live View (clients: #{parse_clients(camera.exid)})",
      timestamp: timestamp,
      url: camera |> Camera.snapshot_url |> EvercamMedia.Util.is_secure_url(camera.exid),
      vendor_exid: Camera.get_vendor_attr(camera, :exid),
      auth: Camera.get_auth_type(camera),
      username: Camera.username(camera),
      password: Camera.password(camera)
    }
  end
end
