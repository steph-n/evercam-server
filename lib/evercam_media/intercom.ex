defmodule EvercamMedia.Intercom do
  alias EvercamMedia.Util
  require Logger

  @intercom_url System.get_env["INTERCOM_URL"]
  @intercom_token System.get_env["INTERCOM_ACCESS_TOKEN"]

  def get_user(user_id) do
    search_string =
      case String.contains?(user_id, "@") do
        true -> "email=#{user_id}"
        _ -> "user_id=#{user_id}"
      end
    url = "#{@intercom_url}?#{search_string}"
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json"]
    response = HTTPoison.get(url, headers) |> elem(1)
    case response.status_code do
      200 -> {:ok, response}
      _ -> {:error, response}
    end
  end

  def get_company(company_id) do
    intercom_url = @intercom_url |> String.replace("users", "companies")
    url = "#{intercom_url}?company_id=#{company_id}"
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json"]
    response = HTTPoison.get(url, headers) |> elem(1)

    case response.status_code do
      200 -> {:ok, response.body |> Jason.decode!}
      _ -> {:error, response}
    end
  end

  def create_company(company_id, company_name) do
    intercom_url = @intercom_url |> String.replace("users", "companies")
    url = "#{intercom_url}"
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json", "Content-Type": "application/json"]
    company_changeset = %{
      company_id: company_id,
      name: company_name,
      created_at: Calendar.DateTime.now_utc |> Calendar.DateTime.Format.unix
    }

    json =
      case Jason.encode(company_changeset) do
        {:ok, json} -> json
        _ -> nil
      end
    HTTPoison.post(url, json, headers)
  end

  def create_user(user, user_agent, requester_ip, status) do
    company_domain = String.split(user.email, "@") |> List.last
    company_id =
      case get_company(company_domain) do
        {:ok, company} -> company["company_id"]
        _ ->
          name = company_domain |> String.split(".") |> List.first |> String.capitalize
          is_valid_company(company_domain, name)
      end
    headers = ["Authorization": "Bearer #{@intercom_token}",  "Accept": "application/json", "Content-Type": "application/json"]
    intercom_new_user = %{
      email: user.email,
      name: user.firstname <> " " <> user.lastname,
      last_seen_user_agent: user_agent,
      last_request_at: user.created_at |> Util.ecto_datetime_to_unix,
      last_seen_ip: requester_ip,
      signed_up_at: user.created_at |> Util.ecto_datetime_to_unix,
      custom_attributes: %{
        viewed_camera: 0,
        viewed_recordings: 0,
        has_shared: false,
        has_snapmail: false
      }
    }
    |> add_userid(user.username)
    |> add_session(user.username, status)
    |> add_status(status)
    |> add_company(company_id)
    |> add_subscribe(status)

    json =
      case Jason.encode(intercom_new_user) do
        {:ok, json} -> json
        _ -> nil
      end

    HTTPoison.post(@intercom_url, json, headers)
    sync_company_with_evercam(user, company_id)
    tag_user(user.email, get_tag_name(company_id))
  end

  defp is_valid_company(company_domain, name) do
    invalid_domains = ["gmail", "yahoo", "hotmail", "outlook", "linkedin", "live"]
    case Enum.any?(invalid_domains, fn x -> String.contains?(name |> String.downcase, x) end) do
      false ->
        create_company(company_domain, name)
        company_domain
      _ -> ""
    end
  end

  defp sync_company_with_evercam(_user, domain) when domain in [nil, ""], do: :noop
  defp sync_company_with_evercam(user, domain) do
    case get_company(domain) do
      {:ok, ic_company} ->
        case Company.by_exid(domain) do
          nil ->
            {:ok, company} = Company.create_company(domain, ic_company["name"],
              %{
                size: ic_company["user_count"],
                session_count: ic_company["session_count"],
                website: ic_company["website"],
                inserted_at: Calendar.DateTime.Parse.unix!(ic_company["created_at"])
              }
            )
            company.id
          %Company{} = company ->
            company_params =
              %{}
              |> add_parameter("field", "size", ic_company["user_count"])
              |> add_parameter("field", "session_count", ic_company["session_count"])
              |> add_parameter("field", "website", ic_company["website"])
              |> add_parameter("field", "name", ic_company["name"])
            Company.update_company(company, company_params)
            company.id
        end
        |> link_company_in_evercam(user, user.id)
      _ -> Logger.debug "Company does not exist."
    end
  end

  defp add_parameter(params, _field, _key, value) when value in [nil, ""], do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end

  defp link_company_in_evercam(_company_id, _user, user_id) when user_id in [nil, ""], do: :noop
  defp link_company_in_evercam(company_id, user, _user_id) do
    User.link_company(user, company_id)
  end

  def update_intercom_user(false, _user, _old_username, _user_agent, _requester_ip), do: :noop
  def update_intercom_user(true, user, old_username, user_agent, requester_ip) do
    headers = ["Authorization": "Bearer #{@intercom_token}",  "Accept": "application/json", "Content-Type": "application/json"]

    case get_user(old_username) do
      {:ok, response} ->
        intercom_user = response.body |> Jason.decode!
        intercom_new_user = %{
          id: intercom_user["id"],
          email: user.email,
          user_id: user.username,
          name: user.firstname <> " " <> user.lastname,
          last_seen_user_agent: user_agent,
          last_seen_ip: requester_ip,
        }
        |> Jason.encode!
        HTTPoison.post(@intercom_url, intercom_new_user, headers)
      _ -> ""
    end
  end

  def tag_user(_email, ""), do: :noop
  def tag_user(email, tag) do
    intercom_url = @intercom_url |> String.replace("users", "tags")
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json", "Content-Type": "application/json"]
    tag_params = %{
      name: tag,
      users: [%{email: email}]
    }

    json =
      case Jason.encode(tag_params) do
        {:ok, json} -> json
        _ -> nil
      end
    HTTPoison.post(intercom_url, json, headers)
  end

  defp add_userid(params, ""), do: params
  defp add_userid(params, id) do
    Map.put(params, :user_id, id)
  end

  defp add_session(params, user_id, _status) when user_id in [nil, ""], do: params
  defp add_session(params, _user_id, "Shared-Non-Registered"), do: Map.put(params, :new_session, false)
  defp add_session(params, _user_id, _status) do
    Map.put(params, :new_session, true)
  end

  defp add_status(params, ""), do: params
  defp add_status(params, status) do
    put_in(params, [:custom_attributes, :status], status)
  end

  defp add_subscribe(params, ""), do: params
  defp add_subscribe(params, "Shared-Non-Registered") do
    Map.put(params, :unsubscribed_from_emails, true)
  end
  defp add_subscribe(params, _status) do
    Map.put(params, :unsubscribed_from_emails, false)
  end

  defp add_company(params, ""), do: params
  defp add_company(params, company_id) do
    Map.put(params, :companies, [%{company_id: "#{company_id}"}])
  end

  def delete_user(user, tries \\ 1)
  def delete_user(_user, 3), do: :noop
  def delete_user(user, tries) do
    company_domain = String.split(user, "@") |> List.last
    url = "#{@intercom_url}?email=#{user}"
    headers = ["Authorization": "Bearer #{@intercom_token}",  "Accept": "application/json", "Content-Type": "application/json"]

    case HTTPoison.delete(url, headers) do
      {:ok, _} -> :noop
      {:error, _} -> delete_user(user, tries + 1)
      _ -> :noop
    end
    case Company.by_exid(company_domain) do
      nil -> :noop
      %Company{} = company ->
        Company.update_company(company, %{size: company.size - 1})
    end
  end

  def intercom_activity(is_create, user, user_agent, requester_ip, status \\ "")
  def intercom_activity(false, _user, _user_agent, _requester_ip, _status), do: :noop
  def intercom_activity(true, user, user_agent, requester_ip, status) do
    Task.start(fn ->
      case get_user(user.username) do
        {:ok, _} ->
          Logger.info "User '#{user.username}' already present at Intercom."
          company_domain = String.split(user.email, "@") |> List.last
          sync_company_with_evercam(user, company_domain)
        {:error, _} -> create_user(user, user_agent, requester_ip, status)
      end
    end)
  end

  def update_user(false, _user, _user_agent, _requester_ip), do: :noop
  def update_user(true, user, user_agent, requester_ip) do
    Task.start(fn ->
      create_user(user, user_agent, requester_ip, "Share-Accepted")
    end)
  end

  def delete_or_update_user(false, _email, _user_agent, _ip, _key), do: :noop
  def delete_or_update_user(true, email, _user_agent, _ip, nil) do
    Task.start(fn ->
      delete_user(email, "email")
    end)
  end
  def delete_or_update_user(true, email, user_agent, ip, _key) do
    Task.start(fn ->
      user = %User{
        username: "",
        firstname: "",
        lastname: "",
        email: email,
        created_at: Calendar.DateTime.now_utc
      }
      create_user(user, user_agent, ip, "Share-Revoked")
    end)
  end

  defp get_tag_name(company_id) do
    case company_id do
      "sisk.ie" -> "Construction"
      "sisk.co.uk" -> "Construction"
      "evercam.io" -> "Evercam team"
      _ -> ""
    end
  end
end
