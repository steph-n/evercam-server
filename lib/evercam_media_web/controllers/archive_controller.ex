defmodule EvercamMediaWeb.ArchiveController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMedia.Util
  alias EvercamMedia.Snapshot.Storage
  import Ecto.Changeset
  import EvercamMedia.TimelapseRecording.S3, only: [load_compare_thumbnail: 2, do_load: 1, get_presigned_url_to_object: 1]
  require Logger

  @status %{pending: 0, processing: 1, completed: 2, failed: 3}

  def swagger_definitions do
    %{
      Archive: swagger_schema do
        title "Archive"
        description ""
        properties do
          id :integer, ""
          camera_id :integer, ""
          exid :string, "", format: "text"
          title :string, "", format: "text"
          from_date :string, "", format: "timestamp"
          to_date :string, "", format: "timestamp"
          status :integer, ""
          requested_by :integer, ""
          embed_time :boolean, ""
          public :boolean, ""
          frames :integer, ""
          url :string, "", format: "character(255)"
          file_name :string, "", format: "character(255)"
          created_at :string, "", format: "timestamp"
        end
      end
    }
  end

  swagger_path :index do
    get "/cameras/{id}/archives"
    summary "Returns the archives list of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 403, "Camera does not exist"
  end

  def index(conn, %{"id" => exid} = params) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    status = params["status"]

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      archives =
        Archive
        |> Archive.by_camera_id(camera.id)
        |> Archive.with_status_if_given(status)
        |> Archive.get_all_with_associations

      compare_archives = Compare.get_by_camera(camera.id)

      render(conn, "index.#{version}.json", %{archives: archives, compares: compare_archives})
    end
  end

  swagger_path :show do
    get "/cameras/{id}/archives/{archive_id}"
    summary "Returns the archives Details."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Archive does not found"
  end

  def show(conn, %{"id" => exid, "archive_id" => archive_id}) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- deliver_content(conn, exid, archive_id, current_user),
         {:ok, media} <- archive_can_list(current_user, camera, archive_id, conn)
    do
      case media do
        %Compare{} = compare -> render(conn, "compare.#{version}.json", %{compare: compare})
        %Archive{} = archive -> render(conn, "show.#{version}.json", %{archive: archive})
      end
    end
  end

  swagger_path :play do
    get "/cameras/{id}/archives/{archive_id}/play"
    summary "Play the requested archive of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Archive does not found"
  end

  def play(conn, %{"id" => exid, "archive_id" => archive_id}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_can_list(current_user, camera, conn) do
      {:ok, url} = get_presigned_url_to_object("#{exid}/clips/#{archive_id}/#{archive_id}.mp4")
      conn
      |> redirect(external: url)
    end
  end

  swagger_path :thumbnail do
    get "/cameras/{id}/archives/{archive_id}/thumbnail"
    summary "Returns the jpeg thumbnail of given archive."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      type :query, :string, "Media type of archive.", required: true, enum: ["clip", "compare", "others"]
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def thumbnail(conn, %{"id" => exid, "archive_id" => archive_id, "type" => media_type}) do
    data =
      case media_type do
        "clip" -> Storage.load_archive_thumbnail(exid, archive_id)
        "compare" -> load_compare_thumbnail(exid, archive_id)
        _ -> Util.default_thumbnail
      end
    conn
    |> put_resp_header("content-type", "image/jpeg")
    |> text(data)
  end

  swagger_path :create do
    post "/cameras/{id}/archives"
    summary "Create new archive."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      title :query, :string, "Name of the clip.", required: true
      from_date :query, :string, "Unix timestamp", required: true
      to_date :query, :string, "Unix timestamp", required: true
      is_nvr_archive :query, :boolean, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 400, "Bad Request"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def create(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      create_clip(params, camera, conn, current_user, String.downcase(params["type"]))
    end
  end

  swagger_path :update do
    patch "/cameras/{id}/archives/{archive_id}"
    summary "Updates full or partial data for an existing archive."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      title :query, :string, ""
      status :query, :string, "",enum: ["pending","processing","completed","failed"]
      public :query, :boolean, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 400, "Bad Request"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def update(conn, %{"id" => exid, "archive_id" => archive_id} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- valid_params(conn, params),
         :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      update_clip(conn, current_user, camera, params, archive_id)
    end
  end

  def retry(conn, %{"id" => exid, "archive_id" => archive_id} = params) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with {:ok, archive} <- archive_exists(conn, archive_id),
         {:ok, _} <- can_list(false, archive, current_user, camera, conn)
    do
      changeset = Archive.changeset(archive, %{status: @status.processing})
      case Repo.update(changeset) do
        {:ok, archive} ->
          updated_archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
          extra = %{
            name: archive.title,
            agent: get_user_agent(conn, params["agent"])
          }
          |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
          CameraActivity.log_activity(current_user, camera, "retry archive creation", extra)

          timezone = Camera.get_timezone(updated_archive.camera)
          unix_from = convert_to_user_time(updated_archive.from_date, timezone)
          unix_to = convert_to_user_time(updated_archive.to_date, timezone)
          start_archive_creation(Application.get_env(:evercam_media, :run_spawn), camera, updated_archive, "#{unix_from}", "#{unix_to}", is_local_clip(updated_archive.type))
          render(conn, "show.#{version}.json", %{archive: updated_archive})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :pending_archives do
    get "/cameras/archives/pending"
    summary "Returns all pending archives."
    parameters do
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end

  def pending_archives(conn, _) do
    %{assigns: %{version: version}} = conn
    requester = conn.assigns[:current_user]

    if requester do
      archive =
        Archive
        |> Archive.with_status_if_given(@status.pending)
        |> Archive.get_one_with_associations

      render(conn, "show.#{version}.json", %{archive: archive})
    else
      render_error(conn, 401, "Unauthorized.")
    end
  end

  swagger_path :delete do
    delete "/cameras/{id}/archives/{archive_id}"
    summary "Delete the archives for given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      archive_id :path, :string, "Unique identifier for archive.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Archives"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def delete(conn, %{"id" => exid, "archive_id" => archive_id} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         {:ok, archive} <- archive_exists(conn, archive_id),
         :ok <- ensure_can_delete(current_user, camera, conn, archive.user.username)
    do
      Archive.delete_by_exid(archive_id)
      spawn(fn -> Storage.delete_archive(camera.exid, archive_id) end)
      extra = %{
        name: archive.title,
        agent: get_user_agent(conn, params["agent"])
      }
      |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
      CameraActivity.log_activity(current_user, camera, "archive deleted", extra)
      json(conn, %{})
    end
  end

  defp create_clip(params, camera, conn, current_user, "url") do
    %{assigns: %{version: version}} = conn
    datetime = get_current_datetime(version)
    changeset =
      params
      |> Map.merge(%{"from_date" => datetime, "to_date" => datetime})
      |> archive_changeset(camera, current_user, @status.completed, version)

    case Repo.insert(changeset) do
      {:ok, archive} ->
        archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
        extra = %{
          name: archive.title,
          agent: get_user_agent(conn, params["agent"])
        }
        |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
        CameraActivity.log_activity(current_user, camera, "saved media URL", extra)
        render(conn |> put_status(:created), "show.#{version}.json", %{archive: archive})
      {:error, changeset} ->
        render_error(conn, 400, Util.parse_changeset(changeset))
    end
  end
  defp create_clip(params, camera, conn, current_user, "file") do
    %{assigns: %{version: version}} = conn
    datetime = get_current_datetime(version)
    changeset =
      params
      |> Map.merge(%{"from_date" => datetime, "to_date" => datetime})
      |> archive_changeset(camera, current_user, @status.completed, version)
    exid = get_field(changeset, :exid)
    changeset = put_change(changeset, :file_name, "#{exid}.#{params["file_extension"]}")

    case Repo.insert(changeset) do
      {:ok, archive} ->
        archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
        extra = %{
          name: archive.title,
          agent: get_user_agent(conn, params["agent"])
        }
        |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
        CameraActivity.log_activity(current_user, camera, "file uploaded", extra)
        copy_uploaded_file(Application.get_env(:evercam_media, :run_spawn), camera.exid, archive.exid, params["file_url"], params["file_extension"])
        render(conn |> put_status(:created), "show.#{version}.json", %{archive: archive})
      {:error, changeset} ->
        render_error(conn, 400, Util.parse_changeset(changeset))
    end
  end
  defp create_clip(params, camera, conn, current_user, "edit") do
    %{assigns: %{version: version}} = conn
    changeset =
      params
      |> Map.merge(%{"to_date" => get_current_datetime(version)})
      |> archive_changeset(camera, current_user, @status.completed, version)
    exid = get_field(changeset, :exid)
    changeset = put_change(changeset, :file_name, "#{exid}.#{params["file_extension"]}")

    case Repo.insert(changeset) do
      {:ok, archive} ->
        archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
        extra = %{
          name: archive.title,
          agent: get_user_agent(conn, params["agent"])
        }
        |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
        CameraActivity.log_activity(current_user, camera, "file uploaded", extra)
        save_edited_image(camera.exid, archive.exid, params["content"])
        render(conn |> put_status(:created), "show.#{version}.json", %{archive: archive})
      {:error, changeset} ->
        render_error(conn, 400, Util.parse_changeset(changeset))
    end
  end
  defp create_clip(params, camera, conn, current_user, _type) do
    %{assigns: %{version: version}} = conn
    timezone = camera |> Camera.get_timezone
    unix_from = params["from_date"]
    unix_to = params["to_date"]
    from_date = clip_date(version, unix_from, timezone)
    to_date = clip_date(version, unix_to, timezone)
    params = update_archive_type(params, params["is_nvr_archive"])
    current_date_time = Calendar.DateTime.now_utc
    changeset = archive_changeset(params, camera, current_user, @status.pending, version)

    cond do
      !changeset.valid? ->
        render_error(conn, 400, Util.parse_changeset(changeset))
      !check_port(camera, params["is_nvr_archive"]) ->
        render_error(conn, 400, "Sorry RTSP port is not available.")
      to_date < from_date ->
        render_error(conn, 400, "To date cannot be less than from date.")
      compare_datetime(current_date_time, from_date) ->
        render_error(conn, 400, "From date cannot be greater than current time.")
      compare_datetime(current_date_time, to_date) ->
        render_error(conn, 400, "To date cannot be greater than current time.")
      to_date == from_date ->
        render_error(conn, 400, "To date and from date cannot be same.")
      date_difference(from_date, to_date) > 3600 ->
        render_error(conn, 400, "Clip duration cannot be greater than 60 minutes.")
      true ->
        case Repo.insert(changeset) do
          {:ok, archive} ->
            archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
            extra = %{
              name: archive.title,
              agent: get_user_agent(conn, params["agent"])
            }
            |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
            CameraActivity.log_activity(current_user, camera, "archive created", extra)
            start_archive_creation(Application.get_env(:evercam_media, :run_spawn), camera, archive, unix_from, unix_to, params["is_nvr_archive"])
            render(conn |> put_status(:created), "show.#{version}.json", %{archive: archive})
          {:error, changeset} ->
            render_error(conn, 400, Util.parse_changeset(changeset))
        end
    end
  end

  defp update_archive_type(params, is_nvr) when is_nvr in [true, "true"] do
    Map.put(params, "type", "local_clip")
  end
  defp update_archive_type(params, _), do: params

  defp is_local_clip("local_clip"), do: true
  defp is_local_clip(_), do: false

  defp archive_changeset(params, camera, current_user, status, version) do
    timezone = camera |> Camera.get_timezone
    from_date = clip_date(version, params["from_date"], timezone)
    to_date = clip_date(version, params["to_date"], timezone)

    archive_params =
      params
      |> Map.delete("id")
      |> Map.delete("api_id")
      |> Map.delete("api_key")
      |> Map.merge(%{
        "requested_by" => current_user.id,
        "camera_id" => camera.id,
        "title" => params["title"],
        "from_date" => from_date,
        "to_date" => to_date,
        "status" => status,
        "url" => params["url"],
        "exid" => Util.generate_unique_exid(params["title"]),
        "type" => params["type"]
      })
    Archive.changeset(%Archive{}, archive_params)
  end

  defp update_clip(conn, user, camera, params, archive_id) do
    %{assigns: %{version: version}} = conn
    case Archive.by_exid(archive_id) do
      nil ->
        render_error(conn, 404, "Archive '#{archive_id}' not found!")
      archive ->
        archive_params =
          %{}
          |> add_parameter("field", "status", params["status"])
          |> add_parameter("field", "title", params["title"])
          |> add_parameter("field", "public", params["public"])
          |> add_parameter("field", "url", params["url"])


        changeset = Archive.changeset(archive, archive_params)
        case Repo.update(changeset) do
          {:ok, archive} ->
            updated_archive = archive |> Repo.preload(:camera) |> Repo.preload(:user)
            extra = %{
              name: archive.title,
              agent: get_user_agent(conn, params["agent"])
            }
            |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
            CameraActivity.log_activity(user, camera, "archive edited", extra)
            save_edited_image(camera.exid, archive.exid, params["content"])
            render(conn, "show.#{version}.json", %{archive: updated_archive})
          {:error, changeset} ->
            render_error(conn, 400, Util.parse_changeset(changeset))
        end
    end
  end

  defp check_port(camera, is_nvr) when is_nvr in [true, "true"] do
    host = Camera.host(camera)
    port = Camera.port(camera, "external", "rtsp")
    case port do
      "" -> true
      nil -> false
      _ -> Util.port_open?(host, "#{port}")
    end
  end
  defp check_port(_, _), do: true

  defp add_parameter(params, _field, _key, nil), do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end

  defp start_archive_creation(true, camera, archive, unix_from, unix_to, is_nvr) when is_nvr in [true, "true"] do
    spawn fn ->
      EvercamMedia.HikvisionNVR.extract_clip_from_stream(camera, archive, unix_from, unix_to)
    end
  end
  defp start_archive_creation(true, _camera, archive, _unix_from, _unix_to, _is_nvr) do
    spawn fn ->
      case Process.whereis(:archive_creator) do
        nil ->
          {:ok, pid} = GenStage.start_link(EvercamMedia.ArchiveCreator.ArchiveCreator, {}, name: :archive_creator)
          GenStage.cast(pid, {:create_archive, archive.exid})
        pid ->
          GenStage.cast(pid, {:create_archive, archive.exid})
      end
    end
  end
  defp start_archive_creation(_mode, _camera, _archive, _unix_from, _unix_to, _is_nvr), do: :noop

  defp copy_uploaded_file(true, camera_id, archive_id, url, extension) do
    spawn fn ->
      Storage.save_archive_file(camera_id, archive_id, url, extension)
      create_thumbnail(camera_id, archive_id, extension)
    end
  end
  defp copy_uploaded_file(_mode, _camera_id, _archive_id, _url, _extension), do: :noop

  defp save_edited_image(_camera_exid, _archive_exid, image_base64) when image_base64 in [nil, ""], do: :noop
  defp save_edited_image(camera_exid, archive_exid, image_base64) do
    spawn fn ->
      image = decode_image(image_base64)
      Storage.save_archive_edited_image(camera_exid, archive_exid, image)
      create_thumbnail(camera_exid, archive_exid, "png")
    end
  end

  defp create_thumbnail(camera_id, archive_id, extension) do
    root_dir = "#{Application.get_env(:evercam_media, :storage_dir)}/#{archive_id}/"
    file_path = "#{root_dir}#{archive_id}.#{extension}"
    case Porcelain.shell("convert -thumbnail 640x480 -background white -alpha remove \"#{file_path}\"[0] #{root_dir}thumb-#{archive_id}.jpg", [err: :out]).out do
      "" -> :noop
      _ -> Porcelain.shell("ffmpeg -i #{file_path} -vframes 1 -vf scale=640:-1 -y #{root_dir}thumb-#{archive_id}.jpg", [err: :out]).out
    end
    Storage.save_archive_thumbnail(camera_id, archive_id, root_dir)
    File.rm_rf(root_dir)
  end

  defp decode_image(image_base64) do
    image_base64
    |> String.replace_leading("data:image/png;base64,", "")
    |> Base.decode64!
  end

  defp ensure_camera_exists(nil, exid, conn) do
    render_error(conn, 404, "Camera '#{exid}' not found!")
  end
  defp ensure_camera_exists(_camera, _exid, _conn), do: :ok

  defp ensure_can_list(current_user, camera, conn) do
    if current_user && Permission.Camera.can_list?(current_user, camera) do
      :ok
    else
      render_error(conn, 401, "Unauthorized.")
    end
  end

  defp archive_can_list(current_user, camera, archive_exid, conn) do
    media =
      case Archive.by_exid(archive_exid) do
        nil -> Compare.by_exid(archive_exid)
        archive -> archive
      end

    case media do
      nil -> render_error(conn, 404, "Archive '#{archive_exid}' not found!")
      %Archive{} = archive -> can_list(archive.public, archive, current_user, camera, conn)
      %Compare{} = compare -> can_list(compare.public, compare, current_user, camera, conn)
    end
  end

  defp can_list(true, media, _current_user, _camera, _conn), do: {:ok, media}
  defp can_list(_, media, current_user, camera, conn) do
    case Permission.Camera.can_list?(current_user, camera) do
      true -> {:ok, media}
      false -> render_error(conn, 403, "Forbidden.")
    end
  end

  defp valid_params(conn, params) do
    if present?(params["id"]) && present?(params["archive_id"]) do
      :ok
    else
      render_error(conn, 400, "Parameters are invalid!")
    end
  end

  defp present?(param) when param in [nil, ""], do: false
  defp present?(_param), do: true

  defp archive_exists(conn, archive_id) do
    case Archive.by_exid(archive_id) do
      nil -> render_error(conn, 404, "Archive '#{archive_id}' not found!")
      %Archive{} = archive -> {:ok, archive}
    end
  end

  defp ensure_can_delete(nil, _camera, conn, _requester), do: render_error(conn, 401, "Unauthorized.")
  defp ensure_can_delete(current_user, camera, conn, requester) do
    case Permission.Camera.can_edit?(current_user, camera) do
      true -> :ok
      false ->
        case current_user.username do
          username when username == requester -> :ok
          _ -> render_error(conn, 403, "Unauthorized.")
        end
    end
  end

  defp convert_to_user_time(date_time, timezone) do
    date_time
    |> Calendar.DateTime.shift_zone!(timezone)
    |> Calendar.DateTime.Format.unix
  end

  defp get_current_datetime(:v1), do: Calendar.DateTime.now_utc |> Calendar.DateTime.Format.unix
  defp get_current_datetime(:v2), do: Calendar.DateTime.now_utc |> Calendar.DateTime.Format.iso8601

  defp clip_date(:v2, clip_datetime, _) when clip_datetime in ["", nil], do: nil
  defp clip_date(:v2, clip_datetime, _), do: Util.datetime_from_iso(clip_datetime)

  defp clip_date(:v1, unix_timestamp, _timezone) when unix_timestamp in ["", nil], do: nil
  defp clip_date(:v1, unix_timestamp, "Etc/UTC"), do: Calendar.DateTime.Parse.unix!(unix_timestamp)
  defp clip_date(:v1, unix_timestamp, timezone) do
    case Util.string_to_integer(unix_timestamp) do
      :error -> "invalid"
      number ->
        number
        |> Calendar.DateTime.Parse.unix!
        |> Calendar.DateTime.to_erl
        |> Calendar.DateTime.from_erl!(timezone)
        |> Calendar.DateTime.shift_zone!("Etc/UTC")
    end

  end

  defp compare_datetime(current_datetime, datetime) do
    case Calendar.DateTime.diff(current_datetime, datetime) do
      {:ok, _, _, :after} -> false
      {:ok, _, _, :before} -> true
    end
  end

  defp date_difference(from, to) do
    case Calendar.DateTime.diff(to, from) do
      {:ok, seconds, _, :after} -> seconds
      _ -> 1
    end
  end

  defp deliver_content(conn, exid, archive_id, requester) do
    archive_with_extension = String.split(archive_id, ".")
    case length(archive_with_extension) do
      2 ->
        [file_name, extension] = archive_with_extension
        ensure_is_public(conn, file_name, requester)
        |> load_file(conn, exid, file_name, extension)
      _ -> :ok
    end
  end

  defp ensure_is_public(conn, archive_exid, nil) do
    with {:ok, archive} <- archive_exists(conn, archive_exid) do
      case archive.public do
        true -> :public
        _ -> :private
      end
    end
  end
  defp ensure_is_public(_conn, _archive_exid, _requester), do: :public

  defp load_file(:private, conn, _camera_exid, file_name, _extension), do: render_error(conn, 404, "Archive '#{file_name}' is not public!")
  defp load_file(:public, conn, camera_exid, file_name, extension) do
    case do_load("#{camera_exid}/clips/#{file_name}/#{file_name}.#{extension}") do
      {:ok, response} ->
        conn
        |> put_resp_header("content-type", get_content_type(extension))
        |> text(response)
      _ -> render_error(conn, 404, "Archive '#{file_name}' not found.")
    end
  end

  defp get_content_type("png"), do: "image/png"
  defp get_content_type("gif"), do: "image/gif"
  defp get_content_type("jpeg"), do: "image/jpeg"
  defp get_content_type("jpg"), do: "image/jpeg"
  defp get_content_type("bmp"), do: "image/bmp"
  defp get_content_type("webp"), do: "image/webp"

  defp get_content_type("mp4"), do: "video/mp4"
  defp get_content_type("webm"), do: "video/webm"
  defp get_content_type("ogg"), do: "video/ogg"
  defp get_content_type("txt"), do: "text/plain"
  defp get_content_type("pdf"), do: "application/pdf"
end
