defmodule EvercamMedia.SyncEvercamToZoho do
  alias EvercamMedia.Zoho
  alias Evercam.Repo
  import Ecto.Query
  require Logger

  def sync_cameras(email_or_username) do
    {:ok, _} = Application.ensure_all_started(:evercam_media)

    Logger.info "Start sync cameras to zoho."

    email_or_username
    |> User.by_username_or_email
    |> Camera.for(false)
    |> Zoho.insert_camera

    Logger.info "Camera(s) sync successfully."
  end

  def sync_contacts() do
    User
    |> Repo.all
    |> Enum.filter(fn(u) -> u.payment_method != 5 end)
    |> Enum.each(fn(user) ->
      case Zoho.get_contact(user.email) do
        {:ok, _contact} -> Logger.info "Contact '#{user.email}' already exists in zoho."
        {:nodata, _message} ->
          Logger.info "Start insert contact '#{user.email}' to zoho."
          {:ok, _contact} = Zoho.insert_contact(user)
          :timer.sleep(10000)
        {:error} -> Logger.error "Error to insert"
      end
    end)
  end

  def sync_camera_sharees(email_or_username) do
    user = User.by_username_or_email(email_or_username)
    cameras = Camera.for(user, false)

    Enum.each(cameras, fn(camera) ->
      zoho_camera =
        case Zoho.get_camera(camera.exid) do
          {:ok, zoho_camera} -> zoho_camera
          _ -> nil
        end

      camera_shares =
        CameraShare
        |> where(camera_id: ^camera.id)
        |> preload(:user)
        |> Repo.all

      Logger.info "Start camera (#{camera.exid}) association."
      request_param = create_request_params(camera_shares, zoho_camera, [])
      case request_param do
        [] -> Logger.info "No pending share for camera #{camera.exid}"
        request -> Zoho.associate_multiple_contact(request)
      end
    end)
  end

  def sync_single_camera_sharees(camera_exid) do
    camera = Camera.get_full(camera_exid)

    zoho_camera =
      case Zoho.get_camera(camera.exid) do
        {:ok, zoho_camera} -> zoho_camera
        _ -> nil
      end

    camera_shares =
      CameraShare
      |> where(camera_id: ^camera.id)
      |> preload(:user)
      |> Repo.all

    case Enum.count(camera_shares) do
      count when count > 49 ->
        camera_shares
        |> Enum.chunk_every(40)
        |> Enum.each(fn(camera_share_chunk) ->
          :timer.sleep(60000)
          do_associate(camera_share_chunk, zoho_camera)
        end)
      _ -> do_associate(camera_shares, zoho_camera)
    end

  end

  def do_associate(camera_shares, zoho_camera) do
    request_param = create_request_params(camera_shares, zoho_camera, [])
    case request_param do
      [] -> Logger.info "No pending share"
      request -> Zoho.associate_multiple_contact(request)
    end
  end

  defp create_request_params([camera_share | rest], zoho_camera, request_param) do
    zoho_contact =
      case Zoho.get_contact(camera_share.user.email) do
        {:ok, zoho_contact} -> zoho_contact
        {:nodata, _message} ->
          case Zoho.insert_contact(camera_share.user) do
            {:ok, contact} -> Map.put(contact, "Full_Name", User.get_fullname(camera_share.user))
            _ -> nil
          end
        {:error} -> nil
      end
    Logger.info "Associate camera (#{zoho_camera["Evercam_ID"]}) with contact (#{zoho_contact["Full_Name"]})."

    case request(zoho_contact, zoho_camera) do
      nil -> create_request_params(rest, zoho_camera, request_param)
      json_object -> create_request_params(rest, zoho_camera, List.insert_at(request_param, -1, json_object))
    end
  end
  defp create_request_params([], _zoho_camera, request_param), do: request_param

  defp request(nil, nil), do: nil
  defp request(nil, _zoho_camera), do: nil
  defp request(_zoho_contact, nil), do: nil
  defp request(zoho_contact, zoho_camera) do
    case Zoho.get_share(zoho_camera["Evercam_ID"], zoho_contact["Full_Name"]) do
      {:ok, _share} -> nil
      _ ->
        %{
          "Share_ID" => Zoho.create_share_id(zoho_camera["Evercam_ID"], zoho_contact["Full_Name"]),
          "Description" => "#{zoho_camera["Name"]} shared with #{zoho_contact["Full_Name"]}",
          "Related_Camera_Sharees" => %{
            name: zoho_camera["Name"],
            id: zoho_camera["id"]
          },
          "Camera_Sharees" => %{
            name: zoho_contact["Full_Name"],
            id: zoho_contact["id"]
          }
        }
    end
  end
end
