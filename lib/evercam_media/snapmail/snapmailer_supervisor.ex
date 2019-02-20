defmodule EvercamMedia.Snapmail.SnapmailerSupervisor do
  @moduledoc """
  Provides function to manage snapmail workers
  """

  use Supervisor
  require Logger
  alias EvercamMedia.Util
  alias EvercamMedia.Snapmail.Snapmailer

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Task.start_link(&initiate_workers/0)
    children = [worker(Snapmailer, [], restart: :permanent)]
    supervise(children, strategy: :simple_one_for_one, max_restarts: 1_000_000)
  end

  @doc """
  Start Snapmail worker
  """
  def start_snapmailer(nil), do: :noop
  def start_snapmailer(snapmail) do
    case get_config(snapmail) do
      {:ok, settings} ->
        Logger.debug "[#{settings.name}] Starting snapmail worker"
        Supervisor.start_child(__MODULE__, [settings])
      {:error, _message, url} ->
        Logger.warn "[#{snapmail.exid}] Skipping snapmail worker as the host is invalid: #{url}"
    end
  end

  @doc """
  Reinitialize snapmail worker with new configuration
  """
  def update_worker(nil, _snapmail), do: :noop
  def update_worker(worker, snapmail) do
    case get_config(snapmail) do
      {:ok, settings} ->
        Logger.debug "Updating worker for #{settings.name}"
        Snapmailer.update_config(worker, settings)
      {:error, _message} ->
        Logger.info "Skipping snapmail worker update as the arguments are invalid"
    end
  end

  def delete_worker(nil), do: :noop
  def delete_worker(worker_pid) do
    Supervisor.terminate_child(__MODULE__, worker_pid)
  end

  @doc """
  Start a worker for each snapmail in the database.

  This function is intended to be called after the EvercamMedia.Snapmail.SnapmailerSupervisor
  is initiated.
  """
  def initiate_workers do
    Logger.info "Initiate workers for snapmail."
    Snapmail.all |> Enum.map(&(start_snapmailer &1))
  end

  @doc """
  Given a snapmail, it returns a map of values required for starting a snapmail worker.
  """
  def get_config(snapmail) do
    {
      :ok,
      %{
        name: snapmail.exid |> String.to_atom,
        config: %{
          snapmail_id: snapmail.id,
          subject: snapmail.subject,
          recipients: snapmail.recipients,
          message: snapmail.message,
          days: Snapmail.get_days_list(snapmail.notify_days),
          notify_time: snapmail.notify_time,
          timezone: Snapmail.get_timezone(snapmail),
          sleep: Snapmail.sleep(snapmail.notify_time, Snapmail.get_timezone(snapmail)),
          is_paused: snapmail.is_paused,
          cameras: get_lists(snapmail.snapmail_cameras)
        }
      }
    }
  end

  def get_lists([]), do: []
  def get_lists(snapmail_cameras) do
    snapmail_cameras
    |> Enum.map(fn(snapmail_camera) -> snapmail_camera.camera end)
    |> Enum.map(fn(camera) ->
      %{
        camera_exid: camera.exid,
        name: camera.name,
        url: Camera.snapshot_url(camera),
        auth: Util.auth(camera),
        timezone: Camera.get_timezone(camera),
        vendor_exid: Camera.get_vendor_attr(camera, :exid)
      }
    end)
  end

  def get_timezone([]), do: "Etc/UTC"
  def get_timezone(snapmail_cameras) do
    camera =
      snapmail_cameras
      |> Enum.map(fn(snapmail_camera) -> snapmail_camera.camera end)
      |> List.first
    case camera.timezone do
      nil -> "Etc/UTC"
      timezone -> timezone
    end
  end
end
