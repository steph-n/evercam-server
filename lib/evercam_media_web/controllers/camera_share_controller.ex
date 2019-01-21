defmodule EvercamMediaWeb.CameraShareController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMedia.Intercom
  alias EvercamMedia.Zoho

  def swagger_definitions do
    %{
      Share: swagger_schema do
        title "Share"
        description ""
        properties do
          id :integer, ""
          camera_id :integer, ""
          user_id :integer, ""
          sharer_id :integer, ""
          kind :string, "", format: "character(50)"
          message :string, "", format: "text"
          created_at :string, "", format: "timestamp"
          updated_at :string, "", format: "timestamp"
        end
      end
    }
  end

  swagger_path :show do
    get "/cameras/{id}/shares"
    summary "Returns the camera permitted users list."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Shares"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 403, "Forbidden camera access"
  end
  def show(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    user = User.by_username_or_email(params["user_id"])

    with :ok <- camera_exists(conn, exid, camera),
         :ok <- user_exists(conn, params["user_id"], user),
         :ok <- user_can_list(conn, current_user, camera, params["user_id"])
    do
      shares =
        cond do
          user == nil && exid == "evercam-remembrance-camera" ->
            []
          user != nil && current_user != nil ->
            CameraShare.user_camera_share(camera, user)
          current_user != nil && caller_can_view(current_user, camera) ->
            CameraShare.camera_shares(camera)
          true ->
            []
        end
        render(conn, "index.json", %{camera_shares: shares, camera: camera, user: current_user})
    end
  end

  swagger_path :create do
    post "/cameras/{id}/shares"
    summary "Provides the camera rights to user."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      email :query, :string, "Share with Evercam registered user", required: true
      rights :query, :string, "", required: true, enum: ["snapshot","minimal+share","full"]
      message :query, :string, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Shares"
    response 201, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist"
  end
  def create(conn, params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(params["id"])
    email_array = ensure_list(params["email"])

    with :ok <- camera_exists(conn, params["id"], camera),
         :ok <- caller_has_permission(conn, caller, camera)
    do
      requester_ip = user_request_ip(conn, params["requester_ip"])
      extra =
        %{ agent: get_user_agent(conn, params["agent"]) }
        |> Map.merge(get_requester_Country(requester_ip, params["u_country"], params["u_country_code"]))

      zoho_camera = %{}

      fetch_shares =
        Enum.reduce(email_array, {[], [], [], Calendar.DateTime.now_utc}, fn email, {shares, share_requests, changes, datetime} = _acc ->
          next_datetime = datetime |> Calendar.DateTime.advance!(2)
          with {:found_user, sharee} <- ensure_user(email)
          do
            case CameraShare.create_share(camera, sharee, caller, params["rights"], params["message"]) do
              {:ok, camera_share} ->
                create_camera_share(Application.get_env(:evercam_media, :run_spawn), caller, sharee, camera, camera_share, extra, next_datetime)
                add_contact_to_zoho(false, zoho_camera, sharee, caller.username)
                {[camera_share | shares], share_requests, changes, next_datetime}
              {:error, changeset} ->
                {shares, share_requests, [attach_email_to_message(changeset, email) | changes], next_datetime}
            end
          else
            {:not_found, email} ->
              case CameraShareRequest.create_share_request(camera, email, caller, params["rights"], params["message"]) do
                {:ok, camera_share_request} ->
                  Application.get_env(:evercam_media, :run_spawn)
                  |> create_camera_share_request(caller, camera, camera_share_request, extra, next_datetime, requester_ip, conn)
                  {shares, [camera_share_request | share_requests], changes, next_datetime}
                {:error, changeset} ->
                  {shares, share_requests, [attach_email_to_message(changeset, email) | changes], next_datetime}
              end
          end
        end)
      {total_shares, share_requests, errors, _} = fetch_shares
      conn
      |> put_status(:created)
      |> render("all_shares.json", %{shares: total_shares, share_requests: share_requests, errors: errors})
    end
  end

  swagger_path :update do
    patch "/cameras/{id}/shares"
    summary "Change the camera rights to user."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      email :query, :string, "Give shared user's email", required: true
      rights :query, :string, "", required: true, enum: ["snapshot","minimal+share","full"]
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Shares"
    response 200, "Success"
    response 400, "Invalid rights specified in request"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Share not found"
  end
  def update(conn, %{"id" => exid, "email" => email, "rights" => rights} = params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    sharee = User.by_username_or_email(email)

    with :ok <- camera_exists(conn, exid, camera),
         :ok <- caller_has_permission(conn, caller, camera),
         :ok <- sharee_exists(conn, email, sharee),
         {:ok, camera_share} <- share_exists(conn, sharee, camera)
    do
      share_changeset = CameraShare.changeset(camera_share, %{rights: rights})
      if share_changeset.valid? do
        CameraShare.update_share(sharee, camera, rights)

        extra =
          %{ with: sharee.email, agent: get_user_agent(conn, params["agent"]) }
          |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
        CameraActivity.log_activity(caller, camera, "updated share", extra)
        Camera.invalidate_user(sharee)
        Camera.invalidate_camera(camera)
        camera_share =
          camera_share
          |> Repo.preload([camera: :access_rights], force: true)
          |> Repo.preload([camera: [access_rights: :access_token]], force: true)
        render(conn, "show.json", %{camera_share: camera_share})
      else
        render_error(conn, 400, Util.parse_changeset(share_changeset))
      end
    end
  end

  swagger_path :shared_users do
    get "/shares/users"
    summary "Returns the shared users."
    parameters do
      camera_id :query, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Shares"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end
  def shared_users(conn, params) do
    caller = conn.assigns[:current_user]

    cond do
      !caller ->
        render_error(conn, 401, "Unauthorized.")
      params["camera_id"] == "evercam-remembrance-camera" -> json(conn, %{})
      true ->
        shared_users =
          caller.id
          |> CameraShare.shared_users(params["camera_id"])
          |> Enum.map(fn(u) -> %{email: u.user.email, name: User.get_fullname(u.user)} end)
          |> Enum.sort
          |> Enum.uniq
        json(conn, shared_users)
    end
  end

  swagger_path :delete do
    delete "/cameras/{id}/shares"
    summary "Delete the camera access."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      email :query, :string, "Give shared user's email", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Shares"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Camera does not exist or Share not found"
  end
  def delete(conn, %{"id" => exid, "email" => email} = params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    sharee = User.by_username_or_email(email)

    with :ok <- camera_exists(conn, exid, camera),
         :ok <- sharee_exists(conn, email, sharee),
         :ok <- user_can_delete_share(conn, caller, sharee, camera),
         {:ok, _share} <- share_exists(conn, sharee, camera)
    do
      CameraShare.delete_share(sharee, camera)
      delete_snapmails(Application.get_env(:evercam_media, :run_spawn), sharee, camera)
      Camera.invalidate_user(sharee)
      Camera.invalidate_camera(camera)
      delete_share_to_zoho(false, exid, User.get_fullname(sharee), caller.username)

      extra =
        %{ with: sharee.email, agent: get_user_agent(conn, params["agent"]) }
        |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
      CameraActivity.log_activity(caller, camera, "stopped sharing", extra)
      json(conn, %{})
    end
  end

  #######################################
  ########## Private Functions ##########
  #######################################

  defp create_camera_share(true, caller, sharee, camera, camera_share, extra, next_datetime) do
    spawn(fn ->
      unless caller == sharee do
        send_email_notification(caller, camera, sharee.email, camera_share.message)
      end
      Camera.invalidate_user(sharee)
      Camera.invalidate_camera(camera)
      CameraActivity.log_activity(caller, camera, "shared", Map.merge(extra, %{with: sharee.email}), next_datetime)
      broadcast_share_to_users(camera)
    end)
  end
  defp create_camera_share(_mode, _, _, _, _, _, _), do: :noop

  defp create_camera_share_request(true, caller, camera, camera_share_request, extra, next_datetime, ip, conn) do
    spawn(fn ->
      send_email_notification(caller, camera, camera_share_request.email, camera_share_request.message, camera_share_request.key)
      CameraActivity.log_activity(caller, camera, "shared", Map.merge(extra, %{with: camera_share_request.email}), next_datetime)
      Intercom.intercom_activity(Application.get_env(:evercam_media, :create_intercom_user), get_user_model(camera_share_request.email), get_user_agent(conn), ip, "Shared-Non-Registered")
    end)
  end
  defp create_camera_share_request(_mode, _, _, _, _, _, _, _), do: :noop

  def broadcast_share_to_users(camera) do
    User.with_access_to(camera)
    |> Enum.each(fn(user) ->
      %{
        camera_id: camera.exid,
        name: camera.name,
        status: camera.is_online,
        cr_status: CloudRecording.recording(camera.cloud_recordings),
        cr_storage_duration: CloudRecording.storage_duration(camera.cloud_recordings)
      }
      |> EvercamMedia.Util.broadcast_camera_share(user.username)
    end)
  end

  defp add_contact_to_zoho(true, zoho_camera, user, user_id) when user_id in ["garda", "gardashared", "construction", "oldconstruction", "smartcities"] do
    spawn fn ->
      contact =
        case Zoho.get_contact(user.email) do
          {:ok, contact} -> contact
          {:nodata, _message} ->
            {:ok, contact} = Zoho.insert_contact(user)
            Map.put(contact, "Full_Name", User.get_fullname(user))
          {:error} -> nil
        end
      case contact do
        nil -> :noop
        zoho_contact -> Zoho.associate_camera_contact(zoho_contact, zoho_camera)
      end
    end
  end
  defp add_contact_to_zoho(_mode, _camera, _user, _user_id), do: :noop

  defp ensure_list(email) do
    case is_binary(email) do
      true -> email |> List.wrap
      false -> email
    end
  end

  defp attach_email_to_message(changeset, email) do
    "#{Util.parse_changeset(changeset) |>  Map.values |> hd} (#{email})"
  end

  defp ensure_user(email) do
    case sharee = User.by_username_or_email(email) do
      nil -> {:not_found, email}
      %User{} -> {:found_user, sharee}
    end
  end

  defp delete_snapmails(true, sharee, camera) do
    spawn(fn ->
      SnapmailCamera.delete_by_sharee(sharee.id, camera.id)
      Snapmail.delete_no_camera_snapmail()
     end)
  end
  defp delete_snapmails(_mode, _, _), do: :noop

  defp delete_share_to_zoho(true, camera_exid, user_fullname, user_id) when user_id in ["garda", "gardashared", "construction", "oldconstruction", "smartcities"] do
    spawn fn ->
      case Zoho.get_share(camera_exid, user_fullname) do
        {:ok, share} -> Zoho.delete_share(share["id"])
        _ -> :noop
      end
    end
  end
  defp delete_share_to_zoho(_mode, _camera_exid, _user_fullname, _user_id), do: :noop

  defp camera_exists(conn, camera_exid, nil), do: render_error(conn, 404, "The #{camera_exid} camera does not exist.")
  defp camera_exists(_conn, _camera_exid, _camera), do: :ok

  defp user_exists(_conn, nil, nil), do: :ok
  defp user_exists(conn, user_id, nil), do: render_error(conn, 404, "User '#{user_id}' does not exist.")
  defp user_exists(_conn, _user_id, _user), do: :ok

  defp caller_has_permission(conn, user, camera) do
    cond do
      Permission.Camera.can_edit?(user, camera) -> :ok
      Permission.Camera.can_share?(user, camera) -> :ok
      true -> render_error(conn, 401, "Unauthorized.")
    end
  end

  defp caller_can_view(user, camera) do
    Permission.Camera.can_edit?(user, camera) || Permission.Camera.can_share?(user, camera)
  end

  defp user_can_list(_conn, _user, _camera, nil), do: :ok
  defp user_can_list(conn, user, camera, user_id) do
    user_id = String.downcase(user_id)

    if !Permission.Camera.can_list?(user, camera) && (user.email != user_id && user.username != user_id) do
      render_error(conn, 401, "Unauthorized.")
    else
      :ok
    end
  end

  defp user_can_delete_share(conn, caller, sharee, camera) do
    cond do
      Permission.Camera.can_list?(caller, camera) -> :ok
      caller == sharee -> :ok
      true -> render_error(conn, 401, "Unauthorized.")
    end
  end

  defp sharee_exists(conn, email, nil), do: render_error(conn, 404, "Sharee '#{email}' not found.")
  defp sharee_exists(_conn, _email, _sharee), do: :ok

  defp share_exists(conn, sharee, camera) do
    case CameraShare.by_user_and_camera(camera.id, sharee.id) do
      nil -> render_error(conn, 404, "Share not found.")
      %CameraShare{} = camera_share -> {:ok, camera_share}
    end
  end

  defp send_email_notification(user, camera, to_email, message) do
    try do
      Task.start(fn ->
        EvercamMedia.UserMailer.camera_shared_notification(user, camera, to_email, message)
      end)
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
    end
  end

  defp send_email_notification(user, camera, to_email, message, share_request_key) do
    try do
      Task.start(fn ->
        EvercamMedia.UserMailer.camera_share_request_notification(user, camera, to_email, message, share_request_key)
      end)
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
    end
  end

  defp get_user_model(email) do
    %User{
      username: email,
      firstname: "",
      lastname: "",
      email: email,
      created_at: Calendar.DateTime.now_utc
    }
  end
end
