defmodule EvercamMedia.Zoho do
  require Logger

  @zoho_url System.get_env["ZOHO_URL"]
  @zoho_auth_token System.get_env["ZOHO_AUTH_TOKEN"]

  def get_camera(camera_exid) do
    url = "#{@zoho_url}Cameras/search?criteria=(Evercam_ID:equals:#{camera_exid})"
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        json_response = Poison.decode!(body)
        camera = Map.get(json_response, "data") |> List.first
        {:ok, camera}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Camera does't exits."}
      _ -> {:error, ""}
    end
  end

  def insert_camera(cameras) do
    url = "#{@zoho_url}Cameras"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]


    camera_object = create_camera_request(cameras, [])
    request = %{"data" => camera_object}

    case HTTPoison.post(url, Poison.encode!(request), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 201}} -> {:ok, body}
      response -> {:error, response}
    end
  end

  def update_camera(cameras, id) do
    url = "#{@zoho_url}Cameras/#{id}"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]

    camera_object = create_camera_request(cameras, [])
    request = %{"data" => camera_object}

    case HTTPoison.put(url, Poison.encode!(request), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        json_response = Poison.decode!(body)
        response = Map.get(json_response, "data") |> List.first
        {:ok, response}
      _ -> {:error}
    end
  end

  def get_account(domain) do
    search_criteria = "(Website:starts_with:http://#{domain})or(Website:starts_with:http://www.#{domain})or(Website:starts_with:https://#{domain})or(Website:starts_with:https://www.#{domain})or(Website:starts_with:www.#{domain})or(Website:starts_with:#{domain})"
    url = "#{@zoho_url}Accounts/search?criteria=(#{search_criteria})"
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        json_response = Poison.decode!(body)
        account = Map.get(json_response, "data") |> List.first
        {:ok, account}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Account does't exits."}
      _ -> {:error}
    end
  end

  def search_account(domain) do
    url = "https://www.zohoapis.com/crm/v2/coql"
    headers = ["Authorization": "#{@zoho_auth_token}"]
    query = "select Account_Name from Accounts where Website like(#{domain})"

    case HTTPoison.post(url, Poison.encode!(%{select_query: query}), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        json_response = Poison.decode!(body)
        account = Map.get(json_response, "data") |> List.first
        {:ok, account}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Account does't exits."}
      error -> {:error, error}
    end
  end

  def get_contact(email) do
    url = "#{@zoho_url}Contacts/search?criteria=(Email:equals:#{email})"
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        json_response = Poison.decode!(body)
        contact = Map.get(json_response, "data") |> List.first
        {:ok, contact}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Contact does't exits."}
      _ -> {:error}
    end
  end

  def insert_contact(user, owner_email \\ nil) do
    url = "#{@zoho_url}Contacts"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]
    domain = user.email |> String.split("@") |> List.last |> String.split(".") |> List.first
    account_name =
      case get_account(domain) do
        {:ok, account} -> account["Account_Name"]
        _ -> get_account_by_owner_email(owner_email)
      end

    contact_xml =
      %{"data" =>
        [%{
          "Contact_lead_source" => "Evercam User",
          "Account_Name" => account_name,
          "First_Name" => "#{user.firstname}",
          "Last_Name" => "#{user.lastname}",
          "Email" => "#{user.email}",
          "Evercam_Signup_Date" => Calendar.Strftime.strftime!(user.created_at, "%Y-%m-%dT%H:%M:%S+00:00")
        }]
      }

    case HTTPoison.post(url, Poison.encode!(contact_xml), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 201}} ->
        json_response = Poison.decode!(body)
        contact = Map.get(json_response, "data") |> List.first
        {:ok, contact["details"]}
      error -> {:error, error}
    end
  end

  def update_contact(id, request_params) do
    url = "#{@zoho_url}Contacts/#{id}"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]

    contact_xml = %{ "data" => request_params }
    case HTTPoison.put(url, Poison.encode!(contact_xml), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} -> {:ok, body}
      error -> {:error, error}
    end
  end

  def delete_contact(id) do
    url = "#{@zoho_url}Contacts/#{id}"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]

    case HTTPoison.delete(url, headers) do
      {:ok, _} -> {:ok}
      error -> {:error, error}
    end
  end

  defp get_account_by_owner_email(nil), do: "No Account"
  defp get_account_by_owner_email(owner_email) do
    domain = owner_email |> String.split("@") |> List.last |> String.split(".") |> List.first
    case get_account(domain) do
      {:ok, account} -> account["Account_Name"]
      _ -> "No Account"
    end
  end

  def get_share(camera_exid, contact_fulname) do
    url = "#{@zoho_url}Cameras_X_Contacts/search?criteria=(Share_ID:equals:#{create_share_id(camera_exid, contact_fulname)})"
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        json_response = Poison.decode!(body)
        share = Map.get(json_response, "data") |> List.first
        {:ok, share}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Share does't exits."}
      _ -> {:error}
    end
  end

  def delete_share(share_id) do
    url = "#{@zoho_url}Cameras_X_Contacts?ids=#{share_id}"
    headers = ["Authorization": "#{@zoho_auth_token}"]

    case HTTPoison.delete(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, "Share deleted successfully."}
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:nodata, "Share does't exits."}
      _ -> {:error}
    end
  end

  def associate_camera_contact(contact, camera) do
    url = "#{@zoho_url}Cameras_X_Contacts"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]

    contact_xml =
      %{ "data" => [%{
          "Share_ID" => create_share_id(camera["Evercam_ID"], contact["Full_Name"]),
          "Description" => "#{camera["Name"]} shared with #{contact["Full_Name"]}",
          "Related_Camera_Sharees" => %{
            name: camera["Name"],
            id: camera["id"]
          },
          "Camera_Sharees" => %{
            name: contact["Full_Name"],
            id: contact["id"]
          }
        }]
      }

    case HTTPoison.post(url, Poison.encode!(contact_xml), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 201}} -> {:ok, body}
      error -> {:error, error}
    end
  end

  def associate_multiple_contact(request_params) do
    url = "#{@zoho_url}Cameras_X_Contacts"
    headers = ["Authorization": "#{@zoho_auth_token}", "Content-Type": "application/x-www-form-urlencoded"]

    contact_xml = %{ "data" => request_params }
    case HTTPoison.post(url, Poison.encode!(contact_xml), headers) do
      {:ok, %HTTPoison.Response{body: body, status_code: 201}} -> {:ok, body}
      error -> {:error, error}
    end
  end

  def create_camera_request([camera | rest], camera_json) do
    url_to_nvr = "http://#{Camera.host(camera, "external")}:#{Camera.get_nvr_port(camera)}"
    evercam_type =
      case camera.owner.email do
        "smartcities@evercam.io" -> "Smart Cities"
        _ -> "Construction"
      end
    camera_obj =
      %{
        "Evercam_ID" => "#{camera.exid}",
        "Evercam_Type" => "#{evercam_type}",
        "Name" => "#{camera.name}",
        "Passwords" => "#{Camera.password(camera)}",
        "URL_to_NVR" => "#{url_to_nvr}"
      }

    create_camera_request(rest, List.insert_at(camera_json, -1, camera_obj))
  end
  def create_camera_request([], camera_json), do: camera_json

  def create_share_id(camera_exid, username) do
    clean_name = username |> EvercamMedia.Util.slugify |> String.replace(" ", "") |> String.replace("-", "") |> String.downcase
    "#{camera_exid}-#{clean_name}"
  end
end
