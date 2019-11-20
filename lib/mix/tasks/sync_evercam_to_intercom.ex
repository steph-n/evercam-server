defmodule EvercamMedia.SyncEvercamToIntercom do
  @moduledoc """
  Tasks for sync evercam data to Intercom
  """
  require Logger
  alias EvercamMedia.Intercom

  @intercom_url System.get_env["INTERCOM_URL"]
  @intercom_token System.get_env["INTERCOM_ACCESS_TOKEN"]
  @fullcontact_key System.get_env["FULLCONTACT_API_KEY"]

  def get_users(next_page \\ nil) do
    api_url =
      case next_page do
        url when url in [nil, ""] -> "#{@intercom_url}"
        next_url -> next_url
      end

    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json"]
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(api_url, headers)
    users = Jason.decode!(body) |> Map.get("users")
    pages = Jason.decode!(body) |> Map.get("pages")
    verify_user(users, Map.get(pages, "next"))
  end

  def update_evercam_users do
    User.all
    |> Enum.each(fn(u) ->
      Logger.debug u.email
      case Intercom.get_user(u.email) do
        {:ok, response} ->
          ic_user = response.body |> Jason.decode!
          urls =
            ic_user["social_profiles"]["social_profiles"]
            |> Enum.reduce(%{}, fn(item, social_links) ->
              add_url_to_params(social_links, item["url"], String.downcase(item["name"]))
            end)
          User.update_user(u, urls)
        _ -> ""
      end
    end)
  end

  defp add_url_to_params(social_links, url, "twitter"), do: Map.merge(social_links, %{twitter_url: url})
  defp add_url_to_params(social_links, url, "linkedin"), do: Map.merge(social_links, %{linkedin_url: url})
  defp add_url_to_params(social_links, _, _), do: social_links

  def get_companies(next_page \\ nil) do
    intercom_url = @intercom_url |> String.replace("users", "companies")
    api_url =
      case next_page do
        url when url in [nil, ""] -> "#{intercom_url}"
        next_url -> next_url
      end

    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json"]
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(api_url, headers)
    companies = Jason.decode!(body) |> Map.get("companies")
    pages = Jason.decode!(body) |> Map.get("pages")
    sync_companies(companies, Map.get(pages, "next"))
  end

  defp sync_companies([intercom_company | rest], next_url) do
    domain = Map.get(intercom_company, "company_id")
    name = Map.get(intercom_company, "name")
    created_at = Map.get(intercom_company, "created_at")
    session_count = Map.get(intercom_company, "session_count")
    user_count = Map.get(intercom_company, "user_count")
    website = Map.get(intercom_company, "website")
    Logger.info "Company: #{name}, Company_id: #{domain}, users-count: #{user_count}, session-count: #{session_count}, website: #{website}, Created_at: #{created_at}"
    case Company.by_exid(domain) do
      nil ->
        {:ok, company} = Company.create_company(domain, name,
          %{
            size: user_count,
            session_count: session_count,
            website: website,
            inserted_at: Calendar.DateTime.Parse.unix!(created_at)
          }
        )
        company.id
      %Company{} = company ->
        company_params =
          %{}
          |> add_parameter("field", "size", user_count)
          |> add_parameter("field", "session_count", session_count)
          |> add_parameter("field", "website", website)
          |> add_parameter("field", "name", name)
        Company.update_company(company, company_params)
        company.id
    end
    |> add_company_id(domain)
    sync_companies(rest, next_url)
  end
  defp sync_companies([], nil), do: Logger.info "Companies sync completed."
  defp sync_companies([], next_url) do
    Logger.info "Start next page companies. URL: #{next_url}"
    get_companies(next_url)
  end

  defp add_parameter(params, _field, _key, value) when value in [nil, ""], do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end

  defp add_company_id(company_id, domain) do
    User.by_email_domain(domain)
    |> Enum.filter(fn(u) -> u.company_id == nil end)
    |> Enum.each(fn(u) ->
      User.link_company(u, company_id)
    end)
  end

  def verify_user([intercom_user | rest], next_url) do
    intercom_email = Map.get(intercom_user, "email")
    user_id = Map.get(intercom_user, "user_id")
    Logger.info "Verifing user email: #{intercom_email}, user_id: #{user_id}"
    case User.by_username_or_email(intercom_email) do
      nil ->
        Logger.info "User deleted from evercam. email: #{intercom_email}"
        Intercom.delete_user(intercom_email)
      %User{} = user -> Logger.info "Intercom user exists in Evercam. email: #{user.email}"
    end
    verify_user(rest, next_url)
  end
  def verify_user([], nil), do: Logger.info "Users sync completed."
  def verify_user([], next_url) do
    Logger.info "Start next page users. URL: #{next_url}"
    get_users(next_url)
  end

  def add_company_to_user(emails) do
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json", "Content-Type": "application/json"]
    emails_list = String.split(emails, ",")

    Enum.each(emails_list, fn(email) ->
      company_domain = String.split(email, "@") |> List.last
      company_id =
        case Intercom.get_company(company_domain) do
          {:ok, company} -> company["company_id"]
          _ ->
            Logger.info "Company does not found for #{email}."
            Intercom.create_company(company_domain, String.split(company_domain, ".") |> List.first)
            company_domain
        end

      case Intercom.get_user(email) do
        {:ok, response} ->
          intercom_user = response.body |> Jason.decode!
          Logger.info "Adding company for email: #{email}, intercom_id: #{intercom_user["id"]}, company_id: #{company_id}"
          intercom_new_user = %{
            id: intercom_user["id"],
            companies: [%{company_id: company_id}]
          }
          |> Jason.encode!
          HTTPoison.post(@intercom_url, intercom_new_user, headers)
        _ -> ""
      end
    end)
  end

  def update_company(ids_names) do
    intercom_url = @intercom_url |> String.replace("users", "companies")
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json", "Content-Type": "application/json"]
    company_list = String.split(ids_names, ",")

    Enum.each(company_list, fn(company) ->
      company_id = String.split(company, ":") |> List.first
      company_name = String.split(company, ":") |> List.last
      case Intercom.get_company(company_id) do
        {:ok, _company} ->
          intercom_new_company = %{
            company_id: company_id,
            name: company_name
          }
          |> Jason.encode!
          HTTPoison.post(intercom_url, intercom_new_company, headers)
          Logger.info "Updated company #{company_id} with name #{company_name}"
        _ ->
          Logger.info "Company does not found for #{company_id}."
      end
    end)
  end

  def start_update_status(next_page \\ nil) do
    api_url =
      case next_page do
        url when url in [nil, ""] -> "#{@intercom_url}"
        next_url -> next_url
      end

    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json"]
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(api_url, headers)
    users = Jason.decode!(body) |> Map.get("users")
    pages = Jason.decode!(body) |> Map.get("pages")
    update_intercom_user_attr(users, Map.get(pages, "next"))
  end

  defp update_intercom_user_attr([intercom_user | rest], next_url) do
    intercom_email = Map.get(intercom_user, "email")
    intercom_user_id = Map.get(intercom_user, "user_id")
    intercom_id = Map.get(intercom_user, "id")
    first_seen = Map.get(intercom_user, "created_at")

    Logger.info "Update attributes of intercom user email: #{intercom_email}"
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json", "Content-Type": "application/json"]

    intercom_new_user = %{
      id: intercom_id,
      email: intercom_email,
      user_id: intercom_user_id,
      signed_up_at: first_seen
    }
    |> Jason.encode!
    HTTPoison.post(@intercom_url, intercom_new_user, headers)
    update_intercom_user_attr(rest, next_url)
  end
  defp update_intercom_user_attr([], nil), do: Logger.info "Users status updated."
  defp update_intercom_user_attr([], next_url) do
    Logger.info "Start next page users. URL: #{next_url}"
    start_update_status(next_url)
  end

  def update_status([intercom_user | rest], next_url) do
    intercom_email = Map.get(intercom_user, "email")
    user_attributes = Map.get(intercom_user, "custom_attributes")
    intercom_id = Map.get(intercom_user, "id")
    case user_attributes["status"] do
      "Shared-Non-Registered" ->
        case User.by_username_or_email(intercom_email) do
          nil -> Logger.info "Intercom user status is corrected. email: #{intercom_email}"
          %User{} = _user -> update_intercom_user_status(intercom_id, intercom_email)
        end
      _ -> :noop
    end
    update_status(rest, next_url)
  end
  def update_status([], nil), do: Logger.info "Users status updated."
  def update_status([], next_url) do
    Logger.info "Start next page users. URL: #{next_url}"
    start_update_status(next_url)
  end

  defp update_intercom_user_status(intercom_id, intercom_email) do
    Logger.info "Update statue of intercom user email: #{intercom_email}"
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "application/json", "Content-Type": "application/json"]

    intercom_new_user = %{
      id: intercom_id,
      email: intercom_email,
      user_id: intercom_email,
      custom_attributes: %{
        status: "Share-Accepted"
      }
    }
    |> Jason.encode!

    HTTPoison.post(@intercom_url, intercom_new_user, headers)
  end

  def update_company_linkedin do
    Company.all
    |> Enum.each(fn(company) ->
      url = "https://api.fullcontact.com/v3/company.enrich"
      case HTTPoison.post(url, '{"domain":"#{company.exid}"}', ["Content-Type": "application/x-www-form-urlencoded", "Authorization": "Bearer #{@fullcontact_key}"]) do
        {:ok,  %HTTPoison.Response{status_code: 200, body: body}} ->
          company = body |> Jason.decode!
          Company.update_company(company, %{linkedin_url: company["linkedin"]})
        {:ok,  %HTTPoison.Response{body: body}} ->
          res = body |> Jason.decode!
          Logger.info res["message"]
        {:error, error} -> Logger.info "#{inspect error}"
      end
      :timer.sleep(10000)
    end)
  end
end
