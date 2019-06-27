defmodule EvercamMediaWeb.CompareController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMedia.Util
  alias EvercamMedia.TimelapseRecording.S3
  alias EvercamMedia.Snapshot.Storage

  def swagger_definitions do
    %{
      Compare: swagger_schema do
        title "Compare"
        description ""
        properties do
          type :string, ""
          to_date :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          title :string, ""
          thumbnail_url :string, ""
          status :string, ""
          requester_name :string, ""
          requester_email :string, ""
          requested_by :string, ""
          public :boolean, "", default: true
          media_url :string, ""
          id :string, ""
          from_date :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          frames :integer, ""
          file_name :string, ""
          embed_code :string, "", format: "character(255)"
          embed_time :boolean, ""
          embed_code :string, ""
          created_at :string, "", format: "ISO8601", example: "2019-02-18T09:00:00.000+00:00"
          camera_id :string, ""
        end
      end
    }
  end

  swagger_path :index do
    get "/cameras/{id}/compares"
    summary "Returns all compares of the requested camera."
    parameters do
      id :path, :string, "Unique identifier for the camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Compares"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end

  def index(conn, %{"id" => camera_exid}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- ensure_camera_exists(camera, camera_exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      compare_archives = Compare.get_by_camera(camera.id)
      render(conn, "index.json", %{compares: compare_archives})
    end
  end

  swagger_path :show do
    get "/cameras/{id}/compares/{compare_id}"
    summary "Returns the single compare."
    parameters do
      compare_id :path, :string, "The ID of the compare being requested.", required: true
      id :path, :string, "Unique identifier for the camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Compares"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Compare archive not found."
  end

  def show(conn, %{"id" => camera_exid, "compare_id" => compare_id}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- ensure_camera_exists(camera, camera_exid, conn),
         :ok <- deliver_content(conn, camera_exid, compare_id),
         {:ok, compare} <- compare_can_list(current_user, camera, compare_id, conn)
    do
      render(conn, "show.json", %{compare: compare})
    end
  end

  def update(conn, %{"id" => camera_exid, "compare_id" => compare_id} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- ensure_camera_exists(camera, camera_exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      case Compare.by_exid(compare_id) do
        nil ->
          render_error(conn, 404, "Compare archive '#{compare_id}' not found!")
        compare_archive ->

          update_params =
            %{}
            |> add_parameter("field", "name", params["name"])
            |> add_parameter("field", "embed_code", params["embed_code"])

          changeset = Compare.changeset(compare_archive, update_params)
          case Repo.update(changeset) do
            {:ok, compare} ->
              render(conn, "show.json", %{compare: compare})
            {:error, changeset} ->
              render_error(conn, 400, Util.parse_changeset(changeset))
          end
      end
    end
  end

  swagger_path :create do
    post "/cameras/{id}/compares"
    summary "Create new compare."
    parameters do
      id :path, :string, "Unique identifier for the camera.", required: true
      exid :query, :string, "Unique identifier for the compare.", required: true
      name :query, :string, "", required: true
      before_date :query, :string, "ISO8601 (2019-02-18T09:00:00.000+00:00)", required: true
      before_image :query, :string, "Before image in base64 format.", required: true
      after_date :query, :string, "ISO8601 (2019-02-18T09:00:00.000+00:00)", required: true
      after_image :query, :string, "After image in base64 format.", required: true
      embed :query, :string, "", required: true
      create_animation :query, :boolean, "", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Compares"
    response 201, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end

  def create(conn, %{"id" => camera_exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- authorized(conn, current_user),
         :ok <- ensure_camera_exists(camera, camera_exid, conn)
    do
      compare_params = %{
        requested_by: current_user.id,
        camera_id: camera.id,
        name: params["name"],
        before_date: convert_to_datetime(params["before_date"]),
        after_date: convert_to_datetime(params["after_date"]),
        embed_code: params["embed"],
        exid: params["exid"]
      }
      |> add_parameter("field", :create_animation, params["create_animation"])
      changeset = Compare.changeset(%Compare{}, compare_params)

      case Repo.insert(changeset) do
        {:ok, compare} ->
          created_compare =
            compare
            |> Repo.preload(:camera)
            |> Repo.preload(:user)

          extra = %{
            name: compare.name,
            agent: get_user_agent(conn, params["agent"])
          }
          |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
          Util.log_activity(current_user, camera, "compare created", extra)
          start_export(Application.get_env(:evercam_media, :run_spawn), camera, compare.exid, params)
          render(conn |> put_status(:created), "show.json", %{compare: created_compare})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :delete_compare do
    delete "/cameras/{id}/compares/{compare_id}"
    summary "Delete the compare."
    parameters do
      compare_id :path, :string, "The ID of the compare being requested.", required: true
      id :path, :string, "Unique identifier for the camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Compares"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Compare archive not found."
  end

  def delete_compare(conn, %{"id" => camera_exid, "compare_id" => compare_id} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- ensure_camera_exists(camera, camera_exid, conn),
         {:ok, compare} <- compare_exists(conn, compare_id),
         :ok <- ensure_can_delete(current_user, camera, conn, compare.user.username)
    do
      Compare.delete_by_exid(compare.exid)
      extra = %{
        name: compare.name,
        agent: get_user_agent(conn, params["agent"])
      }
      |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
      Util.log_activity(current_user, camera, "compare deleted", extra)
      delete_files(compare, camera_exid)
      json(conn, %{})
    end
  end

  defp get_content_type("gif"), do: "image/gif"
  defp get_content_type("mp4"), do: "video/mp4"

  defp start_export(true, camera, compare_exid, params) do
    timezone = Camera.get_timezone(camera)
    before_datetime = convert_to_datetime(params["before_date"])
    after_datetime = convert_to_datetime(params["after_date"])
    before_image = get_image(camera.exid, Calendar.DateTime.Format.unix(before_datetime), timezone)
    after_image = get_image(camera.exid, Calendar.DateTime.Format.unix(after_datetime), timezone)

    spawn fn -> create_animated(params["create_animation"], camera.exid, compare_exid, before_image, after_image) end
    spawn fn -> do_export_image(camera.exid, compare_exid, before_datetime, before_image, "start") end
    spawn fn -> do_export_image(camera.exid, compare_exid, after_datetime, after_image, "end") end
  end
  defp start_export(_is_run, _camera_exid, _compare_exid, _params), do: :nothing

  defp do_export_image(camera_exid, compare_exid, timestamp, image_base64, state) do
    decoded_image = decode_image(image_base64)
    S3.save_compare(camera_exid, compare_exid, timestamp, decoded_image, "compare", state, [acl: :public_read])
  end

  defp export_thumbnail(camera_exid, compare_id, root, evercam_logo) do
    left_arrow = "-draw \"stroke red fill red translate 582,340 rotate -180 scale 4,4 path 'M -17,12  l -12,-9 +12,-9 z'\""
    right_arrow = "-draw \"stroke red fill red translate 680,340 scale 4,4 path 'M -12,6  l -12,-9 +12,-9'\""
    line = "-stroke red -strokewidth 3 -draw 'line 640,0 640,720'"
    cmd = "convert -size 1280x720 xc:None -background None \\( #{root}before_image.jpg -resize '1280x720!' -crop 640x720+0+0 \\) -gravity West -composite \\( #{root}after_image.jpg -resize '1280x720!' -crop 640x720+640+0 \\) -gravity East -composite \\( #{evercam_logo} -resize '100x100!' \\) -geometry +15+15 -gravity SouthEast -composite #{left_arrow} #{right_arrow} #{line} -resize 640x #{root}thumb-#{compare_id}.jpg"
    case Porcelain.shell(cmd).out do
      "" ->
        upload_path = "#{camera_exid}/compares/#{compare_id}/"
        S3.do_save_multiple(%{
          "#{root}thumb-#{compare_id}.jpg" => "#{upload_path}thumb-#{compare_id}.jpg"
        })
      _ -> :noop
    end
  end

  defp create_animated(animation, camera_exid, compare_id, before_image, after_image) when animation in [true, "true"] do
    root = "#{Application.get_env(:evercam_media, :storage_dir)}/#{compare_id}/"
    File.mkdir_p(root)
    File.write("#{root}before_image.jpg", decode_image(before_image))
    File.write("#{root}after_image.jpg", decode_image(after_image))
    evercam_logo = Path.join(Application.app_dir(:evercam_media), "priv/static/images/evercam-logo-white.png")
    spawn fn -> export_thumbnail(camera_exid, compare_id, root, evercam_logo) end
    animated_file = "#{root}#{compare_id}.gif"
    animation_command = "convert -depth 8 -gravity SouthEast -define jpeg:size=1280x720 \\( #{evercam_logo} -resize '100x100!' \\) -write MPR:logo +delete \\( #{root}before_image.jpg -resize '1280x720!' MPR:logo -geometry +15+15 -composite -write MPR:before \\) \\( #{root}after_image.jpg  -resize '1280x720!' MPR:logo -geometry +15+15 -composite -write MPR:after  \\) +append -quantize transparent -colors 250 -unique-colors +repage -write MPR:commonmap +delete MPR:after  -map MPR:commonmap +repage -write MPR:after  +delete MPR:before -map MPR:commonmap +repage -write MPR:before \\( MPR:after -set delay 25 -crop 15x0 -reverse \\) MPR:after \\( MPR:before -set delay 27 -crop 15x0 \\) -set delay 2 -loop 0 -write #{animated_file} +delete 0--2"
    mp4_command = "ffmpeg -f gif -i #{animated_file} -pix_fmt yuv420p -c:v h264_nvenc -movflags +faststart -filter:v crop='floor(in_w/2)*2:floor(in_h/2)*2' #{root}#{compare_id}.mp4"
    command = "#{animation_command} && #{mp4_command}"
    try do
      case Porcelain.shell(command).out do
        "" ->
          upload_path = "#{camera_exid}/compares/#{compare_id}/"
          S3.do_save_multiple(%{
            "#{animated_file}" => "#{upload_path}#{compare_id}.gif",
            "#{root}#{compare_id}.mp4" => "#{upload_path}#{compare_id}.mp4"
          })
          update_compare(compare_id, 1)
        _ -> update_compare(compare_id, 2)
      end
    catch _type, _error ->
      update_compare(compare_id, 2)
    end
    File.rm_rf(root)
  end
  defp create_animated(_animation, _camera_exid, _compare_id, _before_image, _after_image), do: :nothing

  defp update_compare(compare_id, status) do
    compare = Compare.by_exid(compare_id)
    compare_changeset = Compare.changeset(compare, %{status: status})
    Repo.update(compare_changeset)
  end

  defp delete_files(compare, camera_exid) do
    spawn(fn ->
      before_unix = compare.before_date |> Calendar.DateTime.Format.unix
      after_unix = compare.after_date |> Calendar.DateTime.Format.unix
      animation_path = "#{camera_exid}/compares/#{compare.exid}/#{compare.exid}"
      old_animation_path = "#{camera_exid}/compares/#{compare.exid}"
      before_image = "#{S3.construct_compare_bucket_path(camera_exid, compare.exid)}#{S3.construct_compare_file_name(compare.before_date, "start")}"
      old_before_image = "#{S3.construct_bucket_path(camera_exid, before_unix)}#{S3.construct_file_name(before_unix)}"
      after_image = "#{S3.construct_compare_bucket_path(camera_exid, compare.exid)}#{S3.construct_compare_file_name(compare.after_date, "end")}"
      old_after_image = "#{S3.construct_bucket_path(camera_exid, after_unix)}#{S3.construct_file_name(after_unix)}"
      files = [
        "#{after_image}",
        "#{before_image}",
        "#{animation_path}.gif",
        "#{animation_path}.mp4",
        "#{old_after_image}",
        "#{old_before_image}",
        "#{old_animation_path}.gif",
        "#{old_animation_path}.mp4",
        "#{camera_exid}/compares/thumb-#{compare.exid}.jpg",
        "#{camera_exid}/compares/#{compare.exid}/thumb-#{compare.exid}.jpg"
        ]
      S3.delete_object(files)
    end)
  end

  defp decode_image(image_base64) do
    image_base64
    |> String.replace_leading("data:image/jpeg;base64,", "")
    |> Base.decode64!
  end

  defp get_image(camera_exid, datetime, timezone) do
    case Storage.nearest(camera_exid, datetime, :v2, timezone) do
      [snap] -> snap.data
      _ -> ""
    end
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

  defp ensure_can_delete(nil, _camera, conn, _requester), do: render_error(conn, 401, "Unauthorized.")
  defp ensure_can_delete(current_user, camera, conn, requester) do
    case Permission.Camera.can_edit?(current_user, camera) do
      true -> :ok
      false ->
        case current_user.username do
          username when username == requester -> :ok
          _ -> render_error(conn, 401, "Unauthorized.")
        end
    end
  end

  defp compare_can_list(current_user, camera, compare_exid, conn) do
    with {:ok, compare} <- compare_exists(conn, compare_exid) do
      case compare.public do
        true -> {:ok, compare}
        _ ->
          if current_user && Permission.Camera.can_list?(current_user, camera) do
            {:ok, compare}
          else
            render_error(conn, 403, "Forbidden.")
          end
      end
    end
  end

  defp compare_exists(conn, compare_id) do
    case Compare.by_exid(compare_id) do
      nil -> render_error(conn, 404, "Compare archive '#{compare_id}' not found!")
      %Compare{} = compare -> {:ok, compare}
    end
  end

  defp deliver_content(conn, camera_exid, compare_id) do
    format =
      String.split(compare_id, ".")
      |> Enum.filter(fn(n) -> n == "gif" || n == "mp4" end)
      |> List.first

    case format do
      nil -> :ok
      extension -> load_animation(conn, camera_exid, String.replace(compare_id, [".gif", ".mp4"], ""), extension)
    end
  end

  defp load_animation(conn, camera_exid, compare_id, format) do
    {content_type, content} =
      case S3.do_load("#{camera_exid}/compares/#{compare_id}/#{compare_id}.#{format}") do
        {:ok, response} ->
          {get_content_type(format), response}
        {:error, _, _} ->
          evercam_logo_loader = Path.join(Application.app_dir(:evercam_media), "priv/static/images/evercam-logo-loader.gif")
          {"image/gif", File.read!(evercam_logo_loader)}
      end
    conn
    |> put_resp_header("content-type", content_type)
    |> text(content)
  end

  defp add_parameter(params, _field, _key, nil), do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end

  defp convert_to_datetime(value) when value in [nil, ""], do: value
  defp convert_to_datetime(value) do
    case Calendar.DateTime.Parse.rfc3339_utc(value) do
      {:ok, datetime} -> datetime
      {:bad_format, nil} ->
        value
        |> String.to_integer
        |> Calendar.DateTime.Parse.unix!
        |> Calendar.DateTime.to_erl
        |> Calendar.DateTime.from_erl!("Etc/UTC")
    end
  end
end
