defmodule EvercamMedia.SyncEvercamToZoho do
  alias EvercamMedia.Zoho
  alias Evercam.Repo
  import Ecto.Query
  require Logger

  @zoho_url System.get_env["ZOHO_URL"]
  @zoho_auth_token System.get_env["ZOHO_AUTH_TOKEN"]

  def sync_cameras(email_or_username) do
    {:ok, _} = Application.ensure_all_started(:evercam_media)

    Logger.info "Start sync cameras to zoho."

    email_or_username
    |> User.by_username_or_email
    |> Camera.for(false)
    |> Enum.chunk_every(99)
    |> Enum.each(fn(cameras) ->
      cameras
      |> Zoho.insert_camera
      |> IO.inspect
    end)

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

  def add_requestees(iso_datetime) do
    iso_datetime
    |> Calendar.DateTime.Parse.rfc3339_utc
    |> elem(1)
    |> CameraShareRequest.get_all_pending_requests
    |> Enum.each(fn(request) ->
      Logger.info "Email: #{request.email}, Created At: #{request.created_at}"
      case Zoho.get_contact(request.email) do
        {:ok, _contact} -> Logger.info "Contact '#{request.email}' already exists in zoho."
        {:nodata, _message} ->
          Logger.info "Start insert requestee '#{request.email}' to zoho."
          {:ok, _contact} = Zoho.insert_requestee(request.email)
          :timer.sleep(5000)
        {:error} -> Logger.error "Error to insert requestee"
      end
    end)
  end

  def correct_contacts_info() do
    User
    |> Repo.all
    |> Enum.each(fn(user) ->
      case Zoho.get_contact(user.email) do
        {:ok, contact} ->
          Logger.info "Found contact id: #{contact["id"]}, Email: #{contact["Email"]}, Evercam_Signup_Date: #{contact["Evercam_Signup_Date"]}."
          evercam_user_signup_date = user.created_at |> Calendar.Strftime.strftime!("%Y-%m-%dT%H:%M:%S+00:00")
          Zoho.update_contact(contact["id"], [%{"Evercam_Signup_Date" => evercam_user_signup_date}])
          :timer.sleep(1000)
        {:nodata, _message} -> Logger.info "Contact '#{user.email}' does not exists."
        {:error} -> Logger.error "Error to get contact"
      end
    end)
  end

  def sync_accounts_with_contacts(true, page, contacts, account_name) do
    account_name = String.replace(account_name, " ", "%20")
    url = "#{@zoho_url}Contacts/search?criteria=(Account_Name:equals:#{account_name})&page=#{page}"
    Logger.info url
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        zoho_response = Poison.decode!(body)
        info = zoho_response |> Map.get("info")
        contact_lists = Map.get(zoho_response, "data")
        sync_accounts_with_contacts(info["more_records"], info["page"] + 1, contacts ++ contact_lists, account_name)
        {:ok}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Contact does't exits."}
      error -> IO.inspect error
    end
  end
  def sync_accounts_with_contacts(false, _page, contacts, _account_name), do: find_account_and_link(contacts)

  defp find_account_and_link([contact | rest]) do
    domain = contact["Email"] |> String.split("@") |> List.last |> String.split(".") |> List.first
    case Zoho.get_account(domain) do
      {:ok, account} ->
        Logger.info "Update contact email: #{contact["Email"]}, id: #{contact["id"]}, Account Name: #{account["Account_Name"]}"
        Zoho.update_contact(contact["id"], [%{"Account_Name" => account["Account_Name"]}])
        |> IO.inspect
      _ -> ""
    end
    find_account_and_link(rest)
  end
  defp find_account_and_link([]), do: Logger.info "Completed"

  def fix_empty_account_contacts() do
    url = "#{@zoho_url}Contacts?sort_by=Account_Name&sort_order=asc"
    Logger.info url
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        zoho_response = Poison.decode!(body)
        contacts = Map.get(zoho_response, "data")
        link_empty_account(contacts)
        {:ok}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Contact does't exits."}
      error -> IO.inspect error
    end
  end

  defp link_empty_account([contact | rest]) do
    case {contact["Account_Name"], contact["Email"]} do
      {nil, nil} ->
        Logger.info "Email empty."
        Zoho.update_contact(contact["id"], [%{"Account_Name" => "No Account"}])
      {nil, _email} ->
        domain = contact["Email"] |> String.split("@") |> List.last |> String.split(".") |> List.first
        case Zoho.get_account(domain) do
          {:ok, account} ->
            Logger.info "Update contact email: #{contact["Email"]}, id: #{contact["id"]}, Account Name: #{account["Account_Name"]}"
            Zoho.update_contact(contact["id"], [%{"Account_Name" => account["Account_Name"]}])
          _ ->
            Logger.info "Account not found. Email: #{contact["Email"]}"
            Zoho.update_contact(contact["id"], [%{"Account_Name" => "No Account"}])
        end
      {_acc, _email} -> Logger.info "Contact has account"
    end
    link_empty_account(rest)
  end
  defp link_empty_account([]), do: Logger.info "Completed"

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
