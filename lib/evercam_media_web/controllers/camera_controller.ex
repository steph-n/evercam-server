defmodule EvercamMediaWeb.CameraController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias Evercam.Repo
  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.Snapshot.WorkerSupervisor
  alias EvercamMedia.TimelapseRecording.TimelapseRecordingSupervisor
  alias EvercamMedia.Snapshot.CamClient
  alias EvercamMedia.Zoho
  alias EvercamMedia.Util
  require Logger
  import String, only: [to_integer: 1]

  def swagger_definitions do
    %{
      Camera: swagger_schema do
        title "Camera"
        description ""
        properties do
          vendor_name :string, ""
          vendor_id :string, ""
          updated_at :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          timezone :string, ""
          timelapse_recordings :string, ""
          thumbnail_url :string, ""
          rights :string, "", example: "snapshot,list,edit,delete,view,grant~snapshot,grant~view,grant~edit,grant~delete,grant~list"
          proxy_url (Schema.new do
            properties do
              rtmp :string, ""
              hls :string, ""
            end
          end)
          owner :boolean, ""
          owned :string, ""
          offline_reason :string, ""
          name :string, ""
          model_name :string, ""
          model_id :string, ""
          mac_address :string, ""
          location (Schema.new do
            properties do
              lng :integer, ""
              lat :integer, ""
            end
          end)
          last_polled_at :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          last_online_at :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          is_public :boolean, ""
          is_online_email_owner_notification :boolean, ""
          internal (Schema.new do
            properties do
              rtsp (Schema.new do
                properties do
                  port :string, ""
                  mpeg :string, ""
                  h264 :string, ""
                  audio :string, ""
                end
              end)
              http (Schema.new do
                properties do
                  port :string, ""
                  mjpg :string, ""
                  h264 :string, ""
                  camera :string, ""
                end
              end)
              host :string, ""
            end
          end)
          id :string, ""
          external (Schema.new do
            properties do
              rtsp (Schema.new do
                properties do
                  port :string, ""
                  mpeg :string, ""
                  h264 :string, ""
                  audio :string, ""
                end
              end)
              http (Schema.new do
                properties do
                  port :string, ""
                  mjpg :string, ""
                  h264 :string, ""
                  camera :string, ""
                end
              end)
              host :string, ""
            end
          end)
          discoverable :boolean, ""
          created_at :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          cloud_recordings (Schema.new do
            properties do
              storage_duration :integer, ""
              status :string, ""
              schedule (Schema.new do
                properties do
                  wednesday :array, "", description: "00:00-23:59"
                  tuesday :array, "", description: "00:00-23:59"
                  thursday :array, "", description: "00:00-23:59"
                  sunday :array, "", description: "00:00-23:59"
                  saturday :array, "", description: "00:00-23:59"
                  monday :array, "", description: "00:00-23:59"
                  friday :array, "", description: "00:00-23:59"
                end
              end)
              frequency :integer, ""
            end
          end)
          cam_username :boolean, ""
          cam_password :boolean, ""
        end
      end
    }
  end

  swagger_path :port_check do
    get "/cameras/port-check"
    summary "Returns status of the port."
    parameters do
      address :query, :string, "External IP or URL, for example 192.168.1.46"
      port :query, :integer, "HTTP port, for example 8086"
    end
    tag "Cameras"
    response 200, "Success"
  end

  def port_check(conn, params) do
    case check_params(params) do
      {:invalid, message} ->
        json(conn, %{error: message})
      :ok ->
        response = %{
          address: params["address"],
          port: to_integer(params["port"]),
          open: Util.port_open?(params["address"], params["port"])
        }
        json(conn, response)
    end
  end

  swagger_path :index do
    get "/cameras"
    summary "Returns all public and private cameras."
    parameters do
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Cameras"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def index(conn, params) do
    %{assigns: %{version: version}} = conn
    requester = conn.assigns[:current_user]

    case requester do
      nil -> render_error(conn, 404, "Not found.")
      called_user ->
        requested_user =
          case called_user do
            %User{} -> called_user
            %AccessToken{} -> User.by_username(params["user_id"])
          end

        include_shared? =
          case params["include_shared"] do
            "false" -> false
            "true" -> true
            _ -> true
          end

        cameras = ConCache.get_or_store(:cameras, "#{requested_user.username}_#{include_shared?}", fn() ->
          Camera.for(requested_user, include_shared?)
          |> Enum.sort_by(fn(camera) -> String.downcase(camera.name) end)
        end)
        render(conn, "index.#{version}.json", %{cameras: cameras, user: called_user})
    end
  end

  def invalidate_cache(conn, params) do
    message =
      case conn.assigns[:current_user] do
        %User{} ->
          camera = params["id"] |> Camera.get_full
          Camera.invalidate_camera(camera)
          "Camera cache cleared"
        _ -> "Unauthorized."
      end
    json(conn, %{message: message})
  end

  swagger_path :show do
    get "/cameras/{id}"
    summary "Returns the camera details."
    parameters do
      id :path, :string, "The ID of the camera being requested.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Cameras"
    response 200, "Success"
    response 404, "Camera not found"
    response 401, "Invalid API keys"
  end

  def show(conn, params) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    camera =
      params["id"]
      |> String.replace_trailing(".json", "")
      |> Camera.get_full

    case Permission.Camera.can_list?(current_user, camera) do
      true -> render(conn, "show.#{version}.json", %{camera: camera, user: current_user})
      _ -> render_error(conn, 404, "Not found.")
    end
  end

  swagger_path :transfer do
    put "/cameras/{id}"
    summary "Change the ownership of the camera."
    parameters do
      id :path, :string, "The ID of the camera being requested.", required: true
      user_id :query, :string, "The username of the new owner", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Cameras"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 404, "Camera does not exist or Unauthorized"
  end

  def transfer(conn, %{"id" => exid, "user_id" => user_id}) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    user = User.by_username_or_email(user_id)

    with :ok <- is_authorized(conn, current_user),
         :ok <- camera_exists(conn, exid, camera),
         :ok <- user_exists(conn, user_id, user),
         :ok <- has_rights(conn, current_user, camera)
    do
      old_owner = camera.owner
      CameraShare.delete_share(user, camera)
      camera = change_camera_owner(user, camera)
      rights = CameraShare.rights_list("full") |> Enum.join(",")
      CameraShare.create_share(camera, old_owner, user, rights, "")
      update_camera_worker(Application.get_env(:evercam_media, :run_spawn), camera.exid)
      render(conn, "show.#{version}.json", %{camera: camera, user: current_user})
    end
  end

  swagger_path :update do
    patch "/cameras/{id}"
    summary "Update the camera owned by the authenticating user."
    parameters do
      id :path, :string, "The ID of the camera being requested.", required: true
      name :query, :string, "Name of the camera."
      external_http_port :query, :integer, "External HTTP Port, for example 8080"
      external_rtsp_port :query, :string, "Internal RTSP Port, for example 880."
      vendor :query, :string, "Vendor name, for example hikvision"
      model :query, :string, "Model name of the camera being requested"
      timezone :query, :string, "Timezone, for example \"Europe/Dublin\""
      mac_address :query, :string, "Mac address of the camera being requested"
      is_online :query, :boolean, ""
      discoverable :query, :boolean, ""
      location_lng :query, :string, "Longitude, for example 31.422117"
      location_lat :query, :string, "Latitude, for example 73.090051"
      is_public :query, :boolean, ""
      secondary_port :query, :string, "Secondary port of the camera being requested"
      nvr_http_port :query, :string, "HTTP port of NVR."
      nvr_rtsp_port :query, :string, "RTSP port of NVR."
      internal_host :query, :string, "Internal IP or URL."
      internal_http_port :query, :string, "Internal HTTP Port, for example 80."
      internal_rtsp_port :query, :string, "Internal RTSP Port, for example 980."
      cam_username :query, :string, "Username of the camera being requested."
      cam_password :query, :string, "Password of the camera being requested."
      api_id :query, :string, "The Evercam API id for the requester.", required: true
      api_key :query, :string, "The Evercam API key for the requester.", required: true
    end
    tag "Cameras"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end

  def update(conn, %{"id" => exid} = params) do
    %{assigns: %{version: version}} = conn
    caller = conn.assigns[:current_user]
    old_camera = Camera.get_full(exid)

    with :ok <- camera_exists(conn, exid, old_camera),
         do_edit <- Permission.Camera.can_edit?(caller, old_camera),
         :ok <- has_edit_rights(do_edit, conn)
    do
      camera_changeset = camera_update_changeset(old_camera, params, caller.email)
      with true <- camera_changeset.changes == %{} do
        render(conn, "show.#{version}.json", %{camera: old_camera, user: caller})
      else
        false ->
          case Repo.update(camera_changeset) do
            {:ok, camera} ->
              Camera.invalidate_camera(camera)
              camera = Camera.get_full(camera.exid)
              case Application.get_env(:evercam_media, :run_spawn) do
                true ->
                  extra = %{
                    agent: get_user_agent(conn, params["agent"]),
                    cam_settings: add_settings_key(old_camera, camera)
                  }
                  |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
                  Util.log_activity(caller, camera, "camera edited", extra)
                _ -> :noop
              end
              update_camera_worker(Application.get_env(:evercam_media, :run_spawn), camera.exid)
              update_camera_to_zoho(Application.get_env(:evercam_media, :run_spawn), camera, caller.email)
              render(conn, "show.#{version}.json", %{camera: camera, user: caller})
            {:error, changeset} ->
              render_error(conn, 400, Util.parse_changeset(changeset))
          end
      end
    end
  end

  defp add_settings_key(old_camera, camera) do
    %{
      old: set_settings(old_camera),
      new: set_settings(camera)
    }
  end

  defp set_settings(camera) do
    %{
      external_host: Util.deep_get(camera, [:config, "external_host"], ""),
      external_http_port: Util.deep_get(camera, [:config, "external_http_port"], ""),
      external_rtsp_port: Util.deep_get(camera, [:config, "external_rtsp_port"], ""),
      snapshot_url: Util.deep_get(camera, [:config, "snapshots", "jpg"], ""),
      auth: Util.deep_get(camera, [:config, "auth", "basic"], ""),
      vendor_model_name: camera.vendor_model.name,
      vendor_name: camera.vendor_model.vendor.name,
      public: camera.is_public,
      discoverable: camera.discoverable,
      name: camera.name
    }
  end

  swagger_path :delete_camera do
    delete "/cameras/{id}"
    summary "Deletes a camera from Evercam along with any stored media."
    parameters do
      id :path, :string, "The ID of the camera being requested.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Cameras"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 404, "Camera does not exist or Unauthorized"
  end

  def delete_camera(conn, %{"id" => exid} = params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- camera_exists(conn, exid, camera),
         do_delete <- Permission.Camera.can_delete?(caller, camera),
         :ok <- has_delete_rights(do_delete, conn)
    do
      admin_user = User.by_username_or_email("howrya@evercam.io")
      camera_params = %{
        owner_id: admin_user.id,
        discoverable: false,
        is_public: false
      }
      renamed_camera = Map.put(camera, :name, "#{camera.name} (Deleted)")
      update_camera_to_zoho(Application.get_env(:evercam_media, :run_spawn), renamed_camera, caller.email)
      camera
      |> Camera.delete_changeset(camera_params)
      |> Repo.update!

      spawn(fn ->
        extra = %{
          agent: get_user_agent(conn, params["agent"])
        }
        |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
        Util.log_activity(caller, %{ id: 0, exid: camera.exid }, "camera deleted", extra)
      end)
      spawn(fn -> delete_snapshot_worker(camera) end)
      spawn(fn -> delete_camera_worker(camera) end)
      json(conn, %{})
    end
  end

  swagger_path :create do
    post "/cameras"
    summary "Creates a new camera owned by the authenticating user."
    parameters do
      name :query, :string, "Name of the camera.", required: true
      external_host :query, :string, "External IP or URL", required: true
      external_http_port :query, :integer, "External HTTP Port, for example 8080", required: true
      external_rtsp_port :query, :string, "Internal RTSP Port, for example 880."
      vendor :query, :string, "Vendor name, for example hikvision"
      model :query, :string, "Model name of the camera being requested"
      timezone :query, :string, "Timezone, for example \"Europe/Dublin\""
      mac_address :query, :string, "Mac address of the camera being requested"
      is_online :query, :boolean, ""
      discoverable :query, :boolean, ""
      location_lng :query, :string, "Longitude, for example 31.422117"
      location_lat :query, :string, "Latitude, for example 73.090051"
      is_public :query, :boolean, ""
      secondary_port :query, :string, "Secondary port of the camera being requested"
      nvr_http_port :query, :string, "HTTP port of NVR."
      nvr_rtsp_port :query, :string, "RTSP port of NVR."
      internal_host :query, :string, "Internal IP or URL."
      internal_http_port :query, :string, "Internal HTTP Port, for example 80."
      internal_rtsp_port :query, :string, "Internal RTSP Port, for example 980."
      cam_username :query, :string, "Username of the camera being requested."
      cam_password :query, :string, "Password of the camera being requested."
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Cameras"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end

  def create(conn, params) do
    %{assigns: %{version: version}} = conn
    caller = conn.assigns[:current_user]
    with :ok <- is_authorized(conn, caller)
    do
      params
      |> Map.merge(%{"owner_id" => caller.id})
      |> camera_create_changeset(caller.email)
      |> Repo.insert
      |> case do
        {:ok, camera} ->
          full_camera =
            camera
            |> Repo.preload(:owner, force: true)
            |> Repo.preload(:projects, force: true)
            |> Repo.preload(:timelapse_recordings, force: true)
            |> Repo.preload(:cloud_recordings, force: true)
            |> Repo.preload(:vendor_model, force: true)
            |> Repo.preload([vendor_model: :vendor], force: true)

          extra = %{
            agent: get_user_agent(conn, params["agent"])
          }
          |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
          Util.log_activity(caller, camera, "camera created", extra)
          Camera.invalidate_user(caller)
          send_email_notification(Application.get_env(:evercam_media, :run_spawn), caller, full_camera)
          add_camera_to_zoho(Application.get_env(:evercam_media, :run_spawn), full_camera, caller.email)
          conn
          |> put_status(:created)
          |> render("show.#{version}.json", %{camera: full_camera, user: caller})
        {:error, changeset} ->
          Logger.info "[camera-create] [#{inspect params}] [#{inspect Util.parse_changeset(changeset)}]"
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  defp add_camera_to_zoho(true, camera, user_id) when user_id in ["gardashared@evercam.io", "construction@evercam.io", "old-construction@evercam.io", "smartcities@evercam.io"] do
    spawn fn ->
      case Zoho.get_camera(camera.exid) do
        {:ok, _} -> Logger.info "[add_camera_to_zoho] [#{camera.exid}] [Camera already exists]"
        _ -> Zoho.insert_camera([camera])
      end
    end
  end
  defp add_camera_to_zoho(_mode, _camera, _user_id), do: :noop

  defp update_camera_to_zoho(true, camera, user_id) when user_id in ["gardashared@evercam.io", "construction@evercam.io", "old-construction@evercam.io", "smartcities@evercam.io"] do
    spawn fn ->
      case Zoho.get_camera(camera.exid) do
        {:nodata, _} -> Logger.info "[update_camera_to_zoho] [#{camera.exid}] [Camera does not exists]"
        {:ok, zoho_camera} ->
          record_id = zoho_camera["id"]
          Zoho.update_camera([camera], record_id)
      end
    end
  end
  defp update_camera_to_zoho(_mode, _camera, _user_id), do: :noop

  def check_params(params) do
    with :ok <- validate("address", params["address"]),
         :ok <- validate("port", params["port"]),
         do: :ok
  end

  defp validate(key, value) when value in [nil, ""], do: invalid(key)

  defp validate("address", value) do
    case Camera.valid?("address", value) do
      true -> :ok
      _ -> invalid("address")
    end
  end

  defp validate("port", value) when is_integer(value) and value >= 1 and value <= 65_535, do: :ok
  defp validate("port", value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> validate("port", int_value)
      _ -> invalid("port")
    end
  end
  defp validate("port", _), do: invalid("port")

  defp invalid(key), do: {:invalid, "The parameter '#{key}' isn't valid."}

  defp is_authorized(conn, nil) do
    render_error(conn, 401, "Unauthorized.")
  end
  defp is_authorized(_conn, _user), do: :ok

  defp camera_exists(conn, camera_exid, nil) do
    render_error(conn, 404, "The #{camera_exid} camera does not exist.")
  end
  defp camera_exists(_conn, _camera_exid, _camera), do: :ok

  defp user_exists(conn, user_id, nil) do
    render_error(conn, 404, "User '#{user_id}' does not exist.")
  end
  defp user_exists(_conn, _user_id, _user), do: :ok

  defp has_rights(conn, user, camera) do
    case Camera.is_owner?(user, camera) do
      true -> :ok
      _ -> render_error(conn, 403, "Unauthorized.")
    end
  end

  defp update_camera_worker(true, exid) do
    spawn fn ->
      exid |> Camera.get_full |> Camera.invalidate_camera
      camera = exid |> Camera.get_full

      exid
      |> String.to_atom
      |> Process.whereis
      |> WorkerSupervisor.update_worker(camera)

      "timelapse_#{exid}"
      |> String.to_atom
      |> Process.whereis
      |> TimelapseRecordingSupervisor.update_worker(camera)
    end
  end
  defp update_camera_worker(_mode, _exid), do: :noop

  defp change_camera_owner(user, camera) do
    camera
    |> Camera.changeset(%{owner_id: user.id})
    |> Repo.update!
    |> Repo.preload(:owner, force: true)
  end

  defp camera_update_changeset(camera, params, caller_email) do
    camera_params =
      %{
        config: Map.get(camera, :config),
        location_detailed: camera |> Map.get(:location_detailed) |> get_location_detail
      }
      |> construct_camera_parameters("update", params)
      |> add_alert_email(camera.alert_emails, caller_email, params["is_online_email_owner_notification"])

    Camera.changeset(camera, camera_params)
  end

  defp camera_create_changeset(params, caller_email) do
    camera_params =
      %{
        config: %{"snapshots" => %{}},
        location_detailed: %{}
      }
      |> add_parameter("field", :owner_id, params["owner_id"])
      |> construct_camera_parameters("create", params)
      |> add_alert_email([], caller_email, params["is_online_email_owner_notification"])

    Camera.changeset(%Camera{}, camera_params)
  end

  defp construct_camera_parameters(camera, action, params) do
    model = VendorModel.get_model(action, params["vendor"], params["model"])

    camera
    |> add_parameter("field", :name, params["name"])
    |> add_parameter("field", :exid, params["id"])
    |> add_parameter("field", :timezone, params["timezone"])
    |> add_parameter("field", :mac_address, params["mac_address"])
    |> add_parameter("field", :is_online, params["is_online"])
    |> add_parameter("field", :discoverable, params["discoverable"])
    |> add_parameter("field", :location_lng, params["location_lng"])
    |> add_parameter("field", :location_lat, params["location_lat"])
    |> add_parameter("field", :is_public, params["is_public"])
    |> add_parameter("model", :model_id, model)
    |> add_parameter("host", "external_host", params["external_host"])
    |> add_parameter("host", "secondary_port", params["secondary_port"])
    |> add_parameter("host", "external_http_port", params["external_http_port"])
    |> add_parameter("host", "external_rtsp_port", params["external_rtsp_port"])
    |> add_parameter("host", "nvr_http_port", params["nvr_http_port"])
    |> add_parameter("host", "nvr_rtsp_port", params["nvr_rtsp_port"])
    |> add_parameter("host", "internal_host", params["internal_host"])
    |> add_parameter("host", "internal_http_port", params["internal_http_port"])
    |> add_parameter("host", "internal_rtsp_port", params["internal_rtsp_port"])
    |> add_url_parameter(model, "jpg", "jpg", params["jpg_url"])
    |> add_url_parameter(model, "mjpg", "mjpg", params["mjpg_url"])
    |> add_url_parameter(model, "h264", "h264", params["h264_url"])
    |> add_url_parameter(model, "audio", "audio", params["audio_url"])
    |> add_url_parameter(model, "mpeg", "mpeg4", params["mpeg_url"])
    |> add_parameter("auth", "username", params["cam_username"])
    |> add_parameter("auth", "password", params["cam_password"])
    |> add_location_detail("lat", params["location_lat"])
    |> add_location_detail("lng", params["location_lng"])
    |> add_location_detail("dir", params["camera_dir"])
    |> add_location_detail("fov_h", params["camera-fov-h"])
  end

  defp get_location_detail(nil), do: %{}
  defp get_location_detail(location_detailed), do: location_detailed

  defp add_alert_email(params, emails, caller_email, send_notification) when send_notification in [true, "true"] do
    alert_emails =
      emails
      |> Util.get_list
      |> Enum.reject(fn(email) -> email == caller_email end)
      |> List.insert_at(-1, caller_email)
      |> Enum.join(",")

    add_parameter(params, "field", :alert_emails, alert_emails)
  end
  defp add_alert_email(params, emails, caller_email, send_notification) when send_notification in [false, "false"] do
    alert_emails =
      emails
      |> Util.get_list
      |> Enum.reject(fn(email) -> email == caller_email end)
      |> Enum.join(",")

    add_parameter(params, "field", :alert_emails, alert_emails)
  end
  defp add_alert_email(params, _emails, _caller_email, _send_notification), do: params

  defp add_parameter(params, _field, _key, nil), do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end
  defp add_parameter(params, "model", key, value) do
    Map.put(params, key, value.id)
  end
  defp add_parameter(params, "host", key, value) do
    put_in(params, [:config, key], value)
  end
  defp add_parameter(params, "url", key, value) do
    put_in(params, [:config, "snapshots", key], value)
  end
  defp add_parameter(params, "auth", key, value) do
    case is_nil(params[:config]["auth"]) do
      true -> put_in(params, [:config, "auth"], %{"basic" => %{}})
      _ -> params
    end
    |> put_in([:config, "auth", "basic", key], value)
  end

  defp add_location_detail(params, _, value) when value in [nil, ""], do: params
  defp add_location_detail(params, key, value) do
    put_in(params, [:location_detailed, key], value)
  end

  defp add_url_parameter(params, nil, _type, _attr, _custom_value), do: params
  defp add_url_parameter(params, model, type, attr, custom_value) do
    params
    |> do_add_url_parameter(model.exid, type, VendorModel.get_url(model, attr), custom_value)
  end

  defp do_add_url_parameter(params, "other_default", _key, _value, nil), do: params
  defp do_add_url_parameter(params, _model, _key, nil, _custom_value), do: params
  defp do_add_url_parameter(params, "other_default", key, _value, custom_value) do
    put_in(params, [:config, "snapshots", key], custom_value)
  end
  defp do_add_url_parameter(params, _model, key, value, _custom_value) do
    put_in(params, [:config, "snapshots", key], value)
  end

  defp delete_camera_worker(camera) do
    MetaData.delete_by_camera_id(camera.id)
    SnapmailCamera.delete_by_camera_id(camera.id)
    SnapshotExtractor.delete_by_camera_id(camera.id)
    Timelapse.delete_by_camera_id(camera.id)
    CloudRecording.delete_by_camera_id(camera.id)
    CameraShare.delete_by_camera_id(camera.id)
    CameraShareRequest.delete_by_camera_id(camera.id)
    Snapmail.delete_no_camera_snapmail()
    Archive.delete_by_camera(camera.id)
    Compare.delete_by_camera(camera.id)
    Camera.delete_by_id(camera.id)
  end

  defp delete_snapshot_worker(camera) do
    ConCache.delete(:camera_thumbnail, "#{camera.exid}")
    Camera.invalidate_camera(camera)
    CameraActivity.delete_by_camera_id(camera.id)
    Storage.delete_everything_for(camera.exid)
  end

  defp create_thumbnail(camera, mac_address) do
    args = %{
      camera_exid: camera.exid,
      url: Camera.snapshot_url(camera),
      username: Camera.username(camera),
      password: Camera.password(camera),
      auth: Camera.get_auth_type(camera),
      vendor_exid: Camera.get_vendor_attr(camera, :exid),
      timestamp: Calendar.DateTime.Format.unix(Calendar.DateTime.now_utc)
    }
    timestamp = Calendar.DateTime.Format.unix(Calendar.DateTime.now_utc)
    response = CamClient.fetch_snapshot(args)

    case response do
      {:ok, data} ->
        Util.broadcast_snapshot(args[:camera_exid], data, timestamp)
        Storage.save(args[:camera_exid], args[:timestamp], data, args[:notes])
        Camera.update_status(camera, true, mac_address)
      {:error, error} ->
        Logger.error "[#{camera.exid}] [create_thumbnail] [error] [#{inspect error}]"
        Camera.update_status(camera, false, mac_address)
    end
  end

  defp send_email_notification(true, user, camera) do
    try do
      spawn fn ->
        WorkerSupervisor.start_worker(camera)
        mac_address = insert_mac_address(camera)
        create_thumbnail(camera, mac_address)
        EvercamMedia.UserMailer.camera_create_notification(user, camera)
      end
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
    end
  end
  defp send_email_notification(_mode, _user, _camera), do: :noop

  defp insert_mac_address(camera) do
    with {:ok, response} <- EvercamMedia.ONVIFClient.request(Camera.get_camera_info(camera.exid), "device_service", "GetNetworkInterfaces") do
      response |> Map.get("NetworkInterfaces") |> Map.get("Info") |> Map.get("HwAddress")
    else
      {:error, _, _} -> nil
    end
  end
end
