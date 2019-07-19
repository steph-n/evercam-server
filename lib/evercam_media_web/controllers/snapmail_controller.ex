defmodule EvercamMediaWeb.SnapmailController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMedia.Snapmail.SnapmailerSupervisor

  def swagger_definitions do
    %{
      Snapmail: swagger_schema do
        title "Snapmail"
        description ""
        properties do
          title :string, ""
          timezone :string, ""
          requester_name :string, ""
          requester_email :string, ""
          requested_by :string, ""
          recipients :string, ""
          notify_time :string, ""
          notify_days :string, "", example: "Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday"
          message :string, ""
          is_public :boolean, "", default: false
          is_paused :boolean, "", default: false
          id :string, ""
          created_at :string, "", format: "ISO8601", example: "2019-02-15T13:00:04+00:00"
          camera_names :string, ""
          camera_ids :string, ""
        end
      end
    }
  end

  swagger_path :all do
    get "/snapmails"
    summary "Returns all snapmails."
    parameters do
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Snapmails"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
  end

  def all(conn, params) do
    current_user = conn.assigns[:current_user]
    camera = get_camera(params["camera_id"])

    with :ok <- authorized(conn, current_user),
         {:ok, snapmails} <- get_by_user_camera(conn, current_user, camera, params["camera_id"])
    do
      render(conn, "index.json", %{snapmails: snapmails})
    end
  end

  def index(conn, %{"id" => exid}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_list(current_user, camera, conn)
    do
      snapmails = Snapmail.camera_and_user_id(camera.id, current_user.id)
      render(conn, "index.json", %{snapmails: snapmails})
    end
  end

  swagger_path :show do
    get "/snapmails/{id}"
    summary "Returns the requested snapmail details."
    parameters do
      id :path, :string, "The ID of the snapmail being requested."
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Snapmails"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Snapmail not found"
  end

  def show(conn, %{"id" => exid}) do
    current_user = conn.assigns[:current_user]

    with :ok <- authorized(conn, current_user),
         {:ok, snapmail} <- snapmail_exist(conn, exid)
    do
      case snapmail.user_id == current_user.id do
        true -> render(conn, "show.json", %{snapmail: snapmail})
        false -> render_error(conn, 401, "Unauthorized.")
      end
    end
  end

  swagger_path :create do
    post "/snapmails"
    summary "Create new snapmail."
    parameters do
      camera_exids :query, :string, "Multiple IDs of camera in following format (abc,xyz).", required: true
      notify_days :query, :array, "", items: [type: "string", enum: ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]], required: true
      notify_time :query, :string, "Notification time, for example 14:23", required: true
      recipients :query, :string, "Multiple emails in following format (test@example.com,info@example.com).", required: true
      subject :query, :string, "", required: true
      timezone :query, :string, "For example Europe/Dublin", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Snapmails"
    response 201, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Not Found"
  end

  def create(conn, params) do
    current_user = conn.assigns[:current_user]

    with :ok <- authorized(conn, current_user),
         {:ok, cameras} <- ensure_cameras_exist("create", conn, params["camera_exids"], current_user)
    do
      changeset =
        params
        |> add_user_id_params(current_user)
        |> snapmail_create_changeset

      case Repo.insert(changeset) do
        {:ok, snapmail} ->
          SnapmailCamera.insert_cameras(snapmail.id, cameras)
          created_snapmail =
            snapmail
            |> Repo.preload(:user)
            |> Repo.preload(:snapmail_cameras)
            |> Repo.preload([snapmail_cameras: :camera])
          spawn(fn -> start_snapmail_worker(created_snapmail) end)
          render(conn |> put_status(:created), "show.json", %{snapmail: created_snapmail})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :update do
    patch "/snapmails/{id}"
    summary "Update the existing snapmail."
    parameters do
      id :path, :string, "The ID of the snapmail being requested.", required: true
      camera_exids :query, :string, "Multiple IDs of camera in following format (abc,xyz)."
      notify_days :query, :array, "", items: [type: "string", enum: ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]]
      notify_time :query, :string, "Notification, for example 14:23"
      recipients :query, :string, "Multiple emails in following format (test@example.com,info@example.com)."
      subject :query, :string, ""
      timezone :query, :string, "For example Europe/Dublin"
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Snapmails"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Snapmail not found"
  end

  def update(conn, %{"id" => snapmail_exid} = params) do
    current_user = conn.assigns[:current_user]

    with :ok <- authorized(conn, current_user),
         {:ok, cameras} <- ensure_cameras_exist("update", conn, params["camera_exids"], current_user),
         {:ok, snapmail} <- snapmail_exist(conn, snapmail_exid),
         true <- snapmail.user_id == current_user.id
    do
      snapmail_params = construct_snapmail_parameters(%{}, params)
      changeset = Snapmail.changeset(snapmail, snapmail_params)
      case Repo.update(changeset) do
        {:ok, snapmail} ->
          delete_or_update_cameras(cameras, snapmail)
          snapmail =
            snapmail
            |> Repo.preload(:snapmail_cameras, force: true)
            |> Repo.preload([snapmail_cameras: :camera], force: true)
          spawn(fn -> update_snapmail_worker(snapmail) end)
          render(conn, "show.json", %{snapmail: snapmail})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    else
      false -> render_error(conn, 401, "Unauthorized.")
    end
  end

  swagger_path :unsubscribe do
    patch "/snapmails/{id}/unsubscribe/{email}"
    summary "Unsubscribe the snapmail of given email."
    parameters do
      id :path, :string, "The ID of the snapmail being requested."
      email :path, :string, "Give subscribed email."
    end
    tag "Snapmails"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Snapmail not found"
  end

  def unsubscribe(conn, %{"id" => snapmail_exid, "email" => email}) do
    with {:ok, snapmail} <- snapmail_exist(conn, snapmail_exid)
    do
      snapmail_params = %{recipients: remove_email(snapmail.recipients, email)}
      changeset = Snapmail.changeset(snapmail, snapmail_params)
      case Repo.update(changeset) do
        {:ok, snapmail} ->
          spawn(fn -> update_snapmail_worker(snapmail) end)
          render(conn, "show.json", %{snapmail: snapmail})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :delete_snapmail do
    delete "/snapmails/{id}"
    summary "Delete the snapmail"
    parameters do
      id :path, :string, "The ID of the snapmail being requested."
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Snapmails"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Snapmail not found"
  end

  def delete_snapmail(conn, %{"id" => snapmail_exid}) do
    current_user = conn.assigns[:current_user]

    with :ok <- authorized(conn, current_user),
         {:ok, snapmail} <- snapmail_exist(conn, snapmail_exid)
    do
      cond do
        snapmail.user_id != current_user.id ->
          render_error(conn, 401, "Unauthorized.")
        true ->
          spawn(fn -> delete_snapmail_worker(snapmail) end)
          SnapmailCamera.delete_by_snapmail(snapmail.id)
          Snapmail.delete_by_exid(snapmail_exid)
          json(conn, %{})
      end
    end
  end

  defp snapmail_create_changeset(params) do
    snapmail_params =
      %{}
      |> construct_snapmail_parameters(params)

    Snapmail.changeset(%Snapmail{}, snapmail_params)
  end

  defp construct_snapmail_parameters(snapmail, params) do
    snapmail
    |> add_parameter(:subject, params["subject"])
    |> add_parameter(:notify_time, params["notify_time"])
    |> add_parameter(:user_id, params["user_id"])
    |> add_parameter(:recipients, params["recipients"])
    |> add_parameter(:message, params["message"])
    |> add_parameter(:notify_days, params["notify_days"])
    |> add_parameter(:is_public, params["is_public"])
    |> add_parameter(:timezone, params["timezone"])
    |> add_parameter(:is_paused, params["is_paused"])
  end

  defp add_parameter(params, _key, nil), do: params
  defp add_parameter(params, key, value) do
    Map.put(params, key, value)
  end

  defp add_user_id_params(params, nil) do
    Map.merge(params, %{"is_public" => "true"})
  end
  defp add_user_id_params(params, user) do
    Map.merge(params, %{"user_id" => user.id})
  end

  defp ensure_camera_exists(nil, exid, conn) do
    render_error(conn, 404, "Camera '#{exid}' not found!")
  end
  defp ensure_camera_exists(_camera, _exid, _conn), do: :ok

  defp ensure_can_list(current_user, camera, conn) do
    case Permission.Camera.can_list?(current_user, camera) do
      true -> :ok
      _ -> render_error(conn, 401, "Unauthorized.")
    end
  end

  defp get_by_user_camera(_conn, caller, _camera, nil) do
    snapmails = Snapmail.by_user_id(caller.id)
    {:ok, snapmails}
  end
  defp get_by_user_camera(conn, _caller, nil, camera_id), do: render_error(conn, 404, "Camera '#{camera_id}' not found!")
  defp get_by_user_camera(conn, caller, camera, _camera_id) do
    case Permission.Camera.can_list?(caller, camera) do
      true ->
        snapmails = Snapmail.by_camera_id(camera.id, caller.id, conn)
        {:ok, snapmails}
      false -> render_error(conn, 403, "Forbidden.")
    end
  end

  defp snapmail_exist(conn, snapmail_exid) do
    case Snapmail.by_exid(snapmail_exid) do
      nil -> render_error(conn, 404, "Snapmail not found.")
      %Snapmail{} = snapmail -> {:ok, snapmail}
    end
  end

  defp remove_email(emails, unsubscribe) do
    emails
    |> String.split(",", trim: true)
    |> Enum.reject(fn(email) -> email == unsubscribe end)
    |> Enum.join(",")
  end

  defp ensure_cameras_exist("update", _conn, camera_exids, _user) when camera_exids in [nil, ""], do: {:ok, nil}
  defp ensure_cameras_exist("create", conn, camera_exids, _user) when camera_exids in [nil, ""] do
    render_error(conn, 404, %{camera_exids: ["can't be blank"]})
  end
  defp ensure_cameras_exist(_action, conn, camera_exids, user) do
    cameras_list =
      camera_exids
      |> String.split(",", trim: true)
      |> Enum.map(fn(exid) -> %{exid: exid, camera: Camera.get_full(exid)} end)

    cameras_list
    |> Enum.filter(fn(item) -> !Permission.Camera.can_list?(user, item.camera) end)
    |> Enum.map(fn(item) -> item.exid end)
    |> Enum.join(",")
    |> case do
      "" ->
        cameras =
          cameras_list
          |> Enum.map(fn(item) -> %{id: item.camera.id, exid: item.camera.exid} end)
        {:ok, cameras}
      exid ->
        render_error(conn, 404, "User does not have sufficient rights for following camera(s) (#{exid}).")
    end
  end

  defp delete_or_update_cameras(camera_exids, _snapmail) when camera_exids in [nil, ""], do: :noop
  defp delete_or_update_cameras(camera_exids, snapmail) do
    old_camera_exids = get_cameras(snapmail.snapmail_cameras)
    cond do
      camera_exids != old_camera_exids  ->
        grant_cameras = refine_cameras(camera_exids, old_camera_exids)
        remove_cameras = refine_cameras(old_camera_exids, camera_exids)
        SnapmailCamera.insert_cameras(snapmail.id, grant_cameras)
        SnapmailCamera.delete_cameras(snapmail.id, remove_cameras)
      true ->
        :ok
    end
  end

  def get_cameras(snapmail_cameras) do
    snapmail_cameras
    |> Enum.map(fn(snapmail_camera) -> snapmail_camera.camera end)
    |> Enum.map(fn(camera) -> %{id: camera.id, exid: camera.exid} end)
    |> Enum.sort
  end

  defp get_camera(camera_exid) when camera_exid in ["", nil], do: nil
  defp get_camera(camera_exid), do: Camera.get_full(camera_exid)

  defp refine_cameras(list1, list2) do
    list1
    |> Enum.reject(fn(item) -> Enum.member?(list2, item) end)
  end

  defp delete_snapmail_worker(snapmail) do
    snapmail.exid
    |> String.to_atom
    |> Process.whereis
    |> SnapmailerSupervisor.delete_worker
  end

  defp update_snapmail_worker(snapmail) do
    snapmail =
      snapmail
      |> Repo.preload([snapmail_cameras: [camera: :vendor_model]])
      |> Repo.preload([snapmail_cameras: [camera: [vendor_model: :vendor]]])
    snapmail.exid
    |> String.to_atom
    |> Process.whereis
    |> SnapmailerSupervisor.update_worker(snapmail)
  end

  defp start_snapmail_worker(snapmail) do
    snapmail
    |> Repo.preload([snapmail_cameras: [camera: :vendor_model]])
    |> Repo.preload([snapmail_cameras: [camera: [vendor_model: :vendor]]])
    |> SnapmailerSupervisor.start_snapmailer
  end
end
