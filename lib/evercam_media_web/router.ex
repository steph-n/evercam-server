defmodule EvercamMediaWeb.Router do
  use EvercamMediaWeb, :router
  alias EvercamMediaWeb.APIVersion

  pipeline :browser do
    plug :accepts, ["html", "json", "jpg"]
    plug :fetch_session
    plug :fetch_flash
    plug CORSPlug, origin: ["*"]
  end

  pipeline :api_v1 do
    plug :accepts, ["json", "jpg"]
    plug CORSPlug, origin: ["*"]
    plug APIVersion, version: :v1
  end

  pipeline :api_v2 do
    plug :accepts, ["json", "jpg"]
    plug CORSPlug, origin: ["*"]
    plug APIVersion, version: :v2
  end

  pipeline :api_v3 do
    plug :accepts, ["json", "jpg"]
    plug CORSPlug, origin: ["*"]
    plug APIVersion, version: :v3
  end

  def swagger_info do
    %{
      info: %{
        version: "1.0",
        title: "Evercam Server"
      },
      host: "media.evercam.io",
      basePath: "/v2"
    }
  end

  scope "/v2/swagger" do
  forward "/", PhoenixSwagger.Plug.SwaggerUI,
    otp_app: :evercam_media,
    swagger_file: "swagger.json",
    disable_validator: true
end

  pipeline :auth do
    plug EvercamMediaWeb.AuthenticationPlug
  end

  pipeline :jwt_auth do
    plug :accepts, ["json"]
    plug EvercamMediaWeb.JwtAuthPlug
  end

  pipeline :onvif do
    plug EvercamMediaWeb.ONVIFAccessPlug
  end

  scope "/", EvercamMediaWeb do
    pipe_through :browser

    get "/", PageController, :index

    get "/live/:token/index.m3u8", StreamController, :hls
    get "/live/:token/:filename", StreamController, :ts
    get "/on_play", StreamController, :rtmp
    delete "/live/:token", StreamController, :close_stream
    options "/live/:token", StreamController, :nothing
  end

  scope "/v2", EvercamMediaWeb do
    pipe_through :api_v2

    post "/auth/login", UserController, :remote_login
    options "/auth/login", UserController, :nothing

    get "/cameras/port-check", CameraController, :port_check
    post "/cameras/test", SnapshotController, :test

    get "/models", VendorModelController, :index
    options "/models", VendorModelController, :index
    get "/models/:id", VendorModelController, :show
    options "/models/:id", VendorModelController, :show

    get "/vendors", VendorController, :index
    options "/vendors", VendorController, :index
    get "/vendors/:id", VendorController, :show
    options "/vendors/:id", VendorController, :show

    post "/users", UserController, :create
    post "/users/exist/:input", UserController, :user_exist

    get "/public/cameras", PublicController, :index
    get "/storage/stats", PublicController, :storage_stats

    scope "/" do
      pipe_through :auth

      get "/auth/credentials", UserController, :remote_credentials
      options "/auth/credentials", UserController, :nothing
      post "/auth/logout", UserController, :remote_logout
      options "/auth/logout", UserController, :nothing

      # User Route
      get "/users/:id", UserController, :get_user
      get "/users/:id/credentials", UserController, :credentials
      get "/users/telegram/:id/credentials", UserController, :credentialstelegram
      post "/users/:id/password/reset", UserController, :password_reset_token
      options "/users/:id/password/reset", UserController, :nothing
      patch "/users/:id/password", UserController, :password_update
      options "/users/:id/password", UserController, :nothing
      patch "/users/:id", UserController, :update
      options "/users/:id", UserController, :nothing
      delete "/users/:id", UserController, :delete_user
      get "/users/session/activities", UserController, :user_activities
      options "/users/session/activities", UserController, :nothing
      delete "/users/invalidate/cache", UserController, :invalidate_cache

      # Cameras route
      get "/cameras", CameraController, :index
      options "/cameras", CameraController, :nothing
      get "/cameras.json", CameraController, :index
      options "/cameras.json", CameraController, :nothing
      get "/cameras/:id", CameraController, :show
      patch "/cameras/:id", CameraController, :update
      options "/cameras/:id", CameraController, :nothing
      put "/cameras/:id", CameraController, :transfer
      delete "/cameras/:id", CameraController, :delete_camera
      post "/cameras", CameraController, :create
      delete "/cameras/:id/invalidate/cache", CameraController, :invalidate_cache

      # Archive route
      get "/archives", ArchiveController, :user_archives
      options "/archives", ArchiveController, :nothing
      get "/cameras/archives/pending", ArchiveController, :pending_archives
      get "/cameras/:id/archives", ArchiveController, :index
      get "/cameras/:id/archives/:archive_id", ArchiveController, :show
      get "/cameras/:id/archives/:archive_id/play", ArchiveController, :play
      get "/cameras/:id/archives/:archive_id/thumbnail", ArchiveController, :thumbnail
      delete "/cameras/:id/archives/:archive_id", ArchiveController, :delete_archive
      post "/cameras/:id/archives", ArchiveController, :create
      options "/cameras/:id/archives", ArchiveController, :nothing
      put "/cameras/:id/archives/:archive_id", ArchiveController, :retry
      patch "/cameras/:id/archives/:archive_id", ArchiveController, :update
      options "/cameras/:id/archives/:archive_id", ArchiveController, :nothing
      get "/cameras/:id/timelapse/:archive_id/play", TimelapseCreatorController, :play
      options "/cameras/:id/timelapse/:archive_id/play", TimelapseCreatorController, :nothing
      post "/timelapse", TimelapseCreatorController, :create
      options "/timelapse", TimelapseCreatorController, :nothing

      # Logs route
      get "/cameras/:id/logs", LogController, :show
      options "/cameras/:id/logs", LogController, :nothing
      post "/logs", LogController, :create
      options "/logs", LogController, :nothing
      get "/cameras/:id/response-time", LogController, :response_time
      options "/cameras/:id/response-time", LogController, :nothing

      # Snapmails route
      get "/snapmails", SnapmailController, :all
      get "/snapmails/:id", SnapmailController, :show
      get "/cameras/:id/snapmails", SnapmailController, :index
      options "/snapmails", SnapmailController, :nothing
      post "/snapmails", SnapmailController, :create
      patch "/snapmails/:id", SnapmailController, :update
      options "/snapmails/:id", SnapmailController, :nothing
      patch "/snapmails/:id/unsubscribe/:email", SnapmailController, :unsubscribe
      options "/snapmails/:id/unsubscribe/:email", SnapmailController, :nothing
      delete "/snapmails/:id", SnapmailController, :delete_snapmail

      # Cloud recordings route
      get "/cameras/:id/apps/cloud-recording", CloudRecordingController, :show
      options "/cameras/:id/apps/cloud-recording", CloudRecordingController, :nothing
      post "/cameras/:id/apps/cloud-recording", CloudRecordingController, :create

      get "/cameras/:id/apps/cloud-extractions", CloudExtractionsController, :show
      post "/cameras/:id/apps/cloud-extractions", CloudExtractionsController, :create
      options "/cameras/:id/apps/cloud-extractions", CloudExtractionsController, :nothing
      delete "/cameras/:id/apps/cloud-extractions", CloudExtractionsController, :delete_extraction

      # Share and share-request route
      get "/cameras/:id/shares", CameraShareController, :show
      post "/cameras/:id/shares", CameraShareController, :create
      options "/cameras/:id/shares", CameraShareController, :nothing
      patch "/cameras/:id/shares", CameraShareController, :update
      delete "/cameras/:id/shares", CameraShareController, :delete_share
      get "/cameras/:id/shares/requests", CameraShareRequestController, :show
      patch "/cameras/:id/shares/requests", CameraShareRequestController, :update
      delete "/cameras/:id/shares/requests", CameraShareRequestController, :cancel
      options "/cameras/:id/shares/requests", CameraShareRequestController, :nothing
      get "/shares/users", CameraShareController, :shared_users

      # Compare route
      get "/cameras/:id/compares/:compare_id", CompareController, :show
      get "/cameras/:id/compares", CompareController, :index
      post "/cameras/:id/compares", CompareController, :create
      options "/cameras/:id/compares", CompareController, :nothing
      patch "/cameras/:id/compares/:compare_id", CompareController, :update
      options "/cameras/:id/compares/:compare_id", CompareController, :nothing
      delete "/cameras/:id/compares/:compare_id", CompareController, :delete_compare

      # Local recording route
      get "/cameras/:id/nvr/recordings/:year/:month/days", CloudRecordingController, :nvr_days
      get "/cameras/:id/nvr/recordings/:year/:month/:day/hours", CloudRecordingController, :nvr_hours
      get "/cameras/:id/nvr/recordings/stop", CloudRecordingController, :stop
      get "/cameras/:id/nvr/stream", CloudRecordingController, :hikvision_nvr
      get "/cameras/:id/nvr/videos", CloudRecordingController, :get_recording_times
      options "/cameras/:id/nvr/videos", CloudRecordingController, :nothing

      # NVR route
      get "/cameras/:id/nvr/stream/info", NVRController, :get_info
      options "/cameras/:id/nvr/stream/info", NVRController, :nothing
      get "/cameras/:id/nvr/stream/vhinfo", NVRController, :get_vh_info
      options "/cameras/:id/nvr/stream/vhinfo", NVRController, :nothing
      post "/cameras/:id/nvr/snapshots/extract", NVRController, :extract_snapshots
      options "/cameras/:id/nvr/snapshots/extract", NVRController, :nothing
      delete "/cameras/:id/nvr/snapshots/extract", NVRController, :delete_extraction

      # Snapshot route
      get "/cameras/:id/thumbnail", SnapshotController, :thumbnail
      get "/cameras/:id/live/snapshot", SnapshotController, :live
      get "/cameras/:id/live/snapshot.jpg", SnapshotController, :live
      get "/cameras/:id/recordings/snapshots", SnapshotController, :index
      options "/cameras/:id/recordings/snapshots", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/latest", SnapshotController, :latest
      options "/cameras/:id/recordings/snapshots/latest", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/oldest", SnapshotController, :oldest
      options "/cameras/:id/recordings/snapshots/oldest", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:timestamp", SnapshotController, :show
      options "/cameras/:id/recordings/snapshots/:timestamp", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:timestamp/nearest", SnapshotController, :nearest
      options "/cameras/:id/recordings/snapshots/:timestamp/nearest", SnapshotController, :nothing
      post "/cameras/:id/recordings/snapshots", SnapshotController, :create
      delete "/cameras/:id/recordings/snapshots", SnapshotController, :delete
      get "/cameras/:id/recordings/snapshots/:year/:month/days", SnapshotController, :days
      options "/cameras/:id/recordings/snapshots/:year/:month/days", SnapshotController, :nothing

      get "/cameras/:id/recordings/snapshots/:year/:month/:day", SnapshotController, :day
      options "/cameras/:id/recordings/snapshots/:year/:month/:day", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:year/:month/:day/hours", SnapshotController, :hours
      options "/cameras/:id/recordings/snapshots/:year/:month/:day/hours", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:year/:month/:day/:hour", SnapshotController, :hour
      options "/cameras/:id/recordings/snapshots/:year/:month/:day/:hour", SnapshotController, :nothing

      post "/sdk/nvr/reboot", SDKController, :nvr_reboot
      options "/sdk/nvr/reboot", SDKController, :nothing

      # Projects route
      get "/projects", ProjectController, :index
      get "/projects/:id", ProjectController, :show
      post "/projects/:id/overlay", ProjectController, :add_overlay
      options "/projects/:id/overlay", ProjectController, :nothing
      patch "/projects/:id/overlay/:overlay_id", ProjectController, :update_overlay
      options "/projects/:id/overlay/:overlay_id", ProjectController, :nothing
      delete "/projects/:id/overlay/:overlay_id", ProjectController, :delete_overlay
      post "/projects", ProjectController, :create
      options "/projects", ProjectController, :nothing
    end

    scope "/" do
      pipe_through :onvif

      get "/cameras/:id/ptz/status", ONVIFPTZController, :status
      options "/cameras/:id/ptz/status", ONVIFPTZController, :nothing
      get "/cameras/:id/ptz/presets", ONVIFPTZController, :presets
      options "/cameras/:id/ptz/presets", ONVIFPTZController, :nothing
      get "/cameras/:id/ptz/nodes", ONVIFPTZController, :nodes
      options "/cameras/:id/ptz/nodes", ONVIFPTZController, :nothing
      get "/cameras/:id/ptz/configurations", ONVIFPTZController, :configurations
      options "/cameras/:id/ptz/configurations", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/home", ONVIFPTZController, :home
      options "/cameras/:id/ptz/home", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/home/set", ONVIFPTZController, :sethome
      options "/cameras/:id/ptz/home/set", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/presets/:preset_token/set", ONVIFPTZController, :setpreset
      options "/cameras/:id/ptz/presets/:preset_token/set", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/presets/create", ONVIFPTZController, :createpreset
      options "/cameras/:id/ptz/presets/create", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/presets/go/:preset_token", ONVIFPTZController, :gotopreset
      options "/cameras/:id/ptz/presets/go/:preset_token", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/continuous/start/:direction", ONVIFPTZController, :continuousmove
      options "/cameras/:id/ptz/continuous/start/:direction", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/continuous/zoom/:mode", ONVIFPTZController, :continuouszoom
      options "/cameras/:id/ptz/continuous/zoom/:mode", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/continuous/stop", ONVIFPTZController, :stop
      options "/cameras/:id/ptz/continuous/stop", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/relative", ONVIFPTZController, :relativemove
      options "/cameras/:id/ptz/relative", ONVIFPTZController, :nothing

      get "/onvif/v20/:service/:operation", ONVIFController, :invoke
      options "/onvif/v20/:service/:operation", ONVIFController, :nothing
    end
  end

  scope "/v1", EvercamMediaWeb do
    pipe_through :api_v1

    get "/cameras/port-check", CameraController, :port_check
    post "/cameras/test", SnapshotController, :test

    get "/models", VendorModelController, :index
    options "/models", VendorModelController, :index
    get "/models/:id", VendorModelController, :show
    options "/models/:id", VendorModelController, :show

    get "/vendors", VendorController, :index
    options "/vendors", VendorController, :index
    get "/vendors/:id", VendorController, :show
    options "/vendors/:id", VendorController, :show

    post "/users", UserController, :create
    post "/users/exist/:input", UserController, :user_exist

    get "/public/cameras", PublicController, :index

    scope "/" do
      pipe_through :auth

      get "/users/:id", UserController, :get_user
      get "/users/:id/credentials", UserController, :credentials
      get "/users/telegram/:id/credentials", UserController, :credentialstelegram
      post "/users/:id/password/reset", UserController, :password_reset_token
      options "/users/:id/password/reset", UserController, :nothing
      patch "/users/:id/password", UserController, :password_update
      options "/users/:id/password", UserController, :nothing
      patch "/users/:id", UserController, :update
      options "/users/:id", UserController, :nothing
      delete "/users/:id", UserController, :delete_user
      get "/users/session/activities", UserController, :user_activities

      get "/cameras", CameraController, :index
      options "/cameras", CameraController, :nothing
      get "/cameras.json", CameraController, :index
      options "/cameras.json", CameraController, :nothing
      get "/cameras/:id", CameraController, :show
      patch "/cameras/:id", CameraController, :update
      options "/cameras/:id", CameraController, :nothing
      put "/cameras/:id", CameraController, :transfer
      delete "/cameras/:id", CameraController, :delete_camera
      post "/cameras", CameraController, :create

      get "/cameras/:id/thumbnail", SnapshotController, :thumbnail
      get "/cameras/:id/live/snapshot", SnapshotController, :live
      get "/cameras/:id/live/snapshot.jpg", SnapshotController, :live
      get "/cameras/:id/recordings/snapshots", SnapshotController, :index
      options "/cameras/:id/recordings/snapshots", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/latest", SnapshotController, :latest
      options "/cameras/:id/recordings/snapshots/latest", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/oldest", SnapshotController, :oldest
      options "/cameras/:id/recordings/snapshots/oldest", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:timestamp", SnapshotController, :show
      options "/cameras/:id/recordings/snapshots/:timestamp", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:timestamp/nearest", SnapshotController, :nearest
      options "/cameras/:id/recordings/snapshots/:timestamp/nearest", SnapshotController, :nothing
      post "/cameras/:id/recordings/snapshots", SnapshotController, :create
      delete "/cameras/:id/recordings/snapshots", SnapshotController, :delete
      get "/cameras/:id/recordings/snapshots/:year/:month/days", SnapshotController, :days
      options "/cameras/:id/recordings/snapshots/:year/:month/days", SnapshotController, :nothing

      get "/cameras/:id/recordings/snapshots/:year/:month/:day", SnapshotController, :day
      options "/cameras/:id/recordings/snapshots/:year/:month/:day", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:year/:month/:day/hours", SnapshotController, :hours
      options "/cameras/:id/recordings/snapshots/:year/:month/:day/hours", SnapshotController, :nothing
      get "/cameras/:id/recordings/snapshots/:year/:month/:day/:hour", SnapshotController, :hour
      options "/cameras/:id/recordings/snapshots/:year/:month/:day/:hour", SnapshotController, :nothing

      get "/cameras/:id/logs", LogController, :show
      post "/logs", LogController, :create
      options "/logs", LogController, :nothing
      get "/cameras/:id/response-time", LogController, :response_time
      options "/cameras/:id/response-time", LogController, :nothing

      get "/cameras/:id/apps/cloud-recording", CloudRecordingController, :show
      post "/cameras/:id/apps/cloud-recording", CloudRecordingController, :create

      get "/cameras/:id/shares", CameraShareController, :show
      post "/cameras/:id/shares", CameraShareController, :create
      options "/cameras/:id/shares", CameraShareController, :nothing
      patch "/cameras/:id/shares", CameraShareController, :update
      delete "/cameras/:id/shares", CameraShareController, :delete_share
      get "/cameras/:id/shares/requests", CameraShareRequestController, :show
      patch "/cameras/:id/shares/requests", CameraShareRequestController, :update
      delete "/cameras/:id/shares/requests", CameraShareRequestController, :cancel
      options "/cameras/:id/shares/requests", CameraShareRequestController, :nothing
      get "/shares/users", CameraShareController, :shared_users

      get "/cameras/archives/pending", ArchiveController, :pending_archives
      get "/cameras/:id/archives", ArchiveController, :index
      get "/cameras/:id/archives/:archive_id", ArchiveController, :show
      get "/cameras/:id/archives/:archive_id/play", ArchiveController, :play
      get "/cameras/:id/archives/:archive_id/thumbnail", ArchiveController, :thumbnail
      delete "/cameras/:id/archives/:archive_id", ArchiveController, :delete_archive
      post "/cameras/:id/archives", ArchiveController, :create
      options "/cameras/:id/archives", ArchiveController, :nothing
      put "/cameras/:id/archives/:archive_id", ArchiveController, :retry
      patch "/cameras/:id/archives/:archive_id", ArchiveController, :update
      options "/cameras/:id/archives/:archive_id", ArchiveController, :nothing

      get "/snapmails", SnapmailController, :all
      get "/snapmails/:id", SnapmailController, :show
      get "/cameras/:id/snapmails", SnapmailController, :index
      post "/snapmails", SnapmailController, :create
      patch "/snapmails/:id", SnapmailController, :update
      options "/snapmails/:id", SnapmailController, :nothing
      patch "/snapmails/:id/unsubscribe/:email", SnapmailController, :unsubscribe
      options "/snapmails/:id/unsubscribe/:email", SnapmailController, :nothing
      delete "/snapmails/:id", SnapmailController, :delete_snapmail

      get "/cameras/:id/nvr/recordings/:year/:month/days", CloudRecordingController, :nvr_days
      get "/cameras/:id/nvr/recordings/:year/:month/:day/hours", CloudRecordingController, :nvr_hours
      get "/cameras/:id/nvr/recordings/stop", CloudRecordingController, :stop
      get "/cameras/:id/nvr/stream", CloudRecordingController, :hikvision_nvr
      get "/cameras/:id/nvr/videos", CloudRecordingController, :get_recording_times

      get "/cameras/:id/nvr/stream/info", NVRController, :get_info
      options "/cameras/:id/nvr/stream/info", NVRController, :nothing
      get "/cameras/:id/nvr/stream/vhinfo", NVRController, :get_vh_info
      options "/cameras/:id/nvr/stream/vhinfo", NVRController, :nothing
      post "/cameras/:id/nvr/snapshots/extract", NVRController, :extract_snapshots
      options "/cameras/:id/nvr/snapshots/extract", NVRController, :nothing
      delete "/cameras/:id/nvr/snapshots/extract", NVRController, :delete_extraction

      get "/cameras/:id/compares/:compare_id", CompareController, :show
      get "/cameras/:id/compares", CompareController, :index
      post "/cameras/:id/compares", CompareController, :create
      options "/cameras/:id/compares", CompareController, :nothing
      patch "/cameras/:id/compares/:compare_id", CompareController, :update
      options "/cameras/:id/compares/:compare_id", CompareController, :nothing
      delete "/cameras/:id/compares/:compare_id", CompareController, :delete_compare

      post "/sdk/nvr/reboot", SDKController, :nvr_reboot
      options "/sdk/nvr/reboot", SDKController, :nothing

      # Projects route
      get "/projects", ProjectController, :index
      get "/projects/:id", ProjectController, :show
      post "/projects/:id/overlay", ProjectController, :add_overlay
      options "/projects/:id/overlay", ProjectController, :nothing
      patch "/projects/:id/overlay/:overlay_id", ProjectController, :update_overlay
      options "/projects/:id/overlay/:overlay_id", ProjectController, :nothing
      post "/projects", ProjectController, :create
      options "/projects", ProjectController, :nothing
    end

    scope "/" do
      pipe_through :onvif

      get "/cameras/:id/ptz/status", ONVIFPTZController, :status
      options "/cameras/:id/ptz/status", ONVIFPTZController, :nothing
      get "/cameras/:id/ptz/presets", ONVIFPTZController, :presets
      options "/cameras/:id/ptz/presets", ONVIFPTZController, :nothing
      get "/cameras/:id/ptz/nodes", ONVIFPTZController, :nodes
      options "/cameras/:id/ptz/nodes", ONVIFPTZController, :nothing
      get "/cameras/:id/ptz/configurations", ONVIFPTZController, :configurations
      options "/cameras/:id/ptz/configurations", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/home", ONVIFPTZController, :home
      options "/cameras/:id/ptz/home", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/home/set", ONVIFPTZController, :sethome
      options "/cameras/:id/ptz/home/set", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/presets/:preset_token/set", ONVIFPTZController, :setpreset
      options "/cameras/:id/ptz/presets/:preset_token/set", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/presets/create", ONVIFPTZController, :createpreset
      options "/cameras/:id/ptz/presets/create", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/presets/go/:preset_token", ONVIFPTZController, :gotopreset
      options "/cameras/:id/ptz/presets/go/:preset_token", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/continuous/start/:direction", ONVIFPTZController, :continuousmove
      options "/cameras/:id/ptz/continuous/start/:direction", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/continuous/zoom/:mode", ONVIFPTZController, :continuouszoom
      options "/cameras/:id/ptz/continuous/zoom/:mode", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/continuous/stop", ONVIFPTZController, :stop
      options "/cameras/:id/ptz/continuous/stop", ONVIFPTZController, :nothing
      post "/cameras/:id/ptz/relative", ONVIFPTZController, :relativemove
      options "/cameras/:id/ptz/relative", ONVIFPTZController, :nothing

      get "/onvif/v20/:service/:operation", ONVIFController, :invoke
      options "/onvif/v20/:service/:operation", ONVIFController, :nothing
    end
  end
end
