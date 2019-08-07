defmodule EvercamMedia do
  use Application
  require Logger
  import EvercamMedia.Util, only: [load_storage_servers: 1]

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      {ConCache,[ttl_check_interval: :timer.seconds(0.1), global_ttl: :timer.seconds(2.5), name: :cache]},
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(0.1), global_ttl: :timer.seconds(1.5), name: :snapshot_schedule]}, id: :snapshot_schedule),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(0.1), global_ttl: :timer.minutes(1), name: :camera_lock]}, id: :camera_lock),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(1), global_ttl: :timer.hours(1), name: :users]}, id: :users),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(1), global_ttl: :timer.hours(1), name: :camera]}, id: :camera),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(1), global_ttl: :timer.hours(1), name: :cameras]}, id: :cameras),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(1), global_ttl: :timer.hours(1), name: :camera_full]}, id: :camera_full),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.hours(1), global_ttl: :timer.hours(24), name: :snapshot_error]}, id: :snapshot_error),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.hours(2), global_ttl: :timer.hours(24), name: :camera_thumbnail]}, id: :camera_thumbnail),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.hours(2), global_ttl: :timer.hours(24), name: :current_camera_status]}, id: :current_camera_status),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.hours(2), global_ttl: :timer.hours(6), name: :camera_response_times]}, id: :camera_response_times),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.seconds(1), global_ttl: :timer.hours(1), name: :do_camera_request]}, id: :do_camera_request),
      Supervisor.child_spec({ConCache, [ttl_check_interval: :timer.hours(2), global_ttl: :timer.hours(24), name: :camera_recording_days]}, id: :camera_recording_days),
      worker(EvercamMedia.Scheduler, []),
      worker(EvercamMedia.Janitor, []),
      worker(EvercamMedia.StorageJson, []),
      supervisor(EvercamMediaWeb.Endpoint, []),
      supervisor(EvercamMedia.Snapshot.StreamerSupervisor, []),
      supervisor(EvercamMedia.Snapshot.WorkerSupervisor, []),
      supervisor(EvercamMedia.Snapmail.SnapmailerSupervisor, []),
      supervisor(EvercamMedia.SnapshotExtractor.ExtractorSupervisor, []),
      supervisor(EvercamMedia.EvercamBot.TelegramSupervisor, []),
      :hackney_pool.child_spec(:snapshot_pool, [timeout: 5000, max_connections: 1000]),
      :hackney_pool.child_spec(:seaweedfs_upload_pool, [timeout: 5000, max_connections: 1000]),
      :hackney_pool.child_spec(:seaweedfs_download_pool, [timeout: 5000, max_connections: 1000]),
    ]

    :ets.new(:extractions, [:public, :named_table])
    :ets.new(:storage_servers, [:set, :public, :named_table])
    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    load_storage_servers([])
    opts = [strategy: :one_for_one, name: EvercamMedia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    EvercamMediaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
