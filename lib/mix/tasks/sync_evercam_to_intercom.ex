defmodule EvercamMedia.SyncEvercamToIntercom do
  require Logger
  alias EvercamMedia.Intercom

  @intercom_url System.get_env["INTERCOM_URL"]
  @intercom_token System.get_env["INTERCOM_ACCESS_TOKEN"]

  def get_users(next_page \\ nil) do
    api_url =
      case next_page do
        url when url in [nil, ""] -> "#{@intercom_url}"
        next_url -> next_url
      end

    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "Accept:application/json"]
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(api_url, headers)
    users = Poison.decode!(body) |> Map.get("users")
    pages = Poison.decode!(body) |> Map.get("pages")
    verify_user(users, Map.get(pages, "next"))
  end

  def verify_user([intercom_user | rest], next_url) do
    intercom_email = Map.get(intercom_user, "email")
    user_id = Map.get(intercom_user, "user_id")
    Logger.info "Verifing user email: #{intercom_email}, user_id: #{user_id}"
    case User.by_username_or_email(intercom_email) do
      nil ->
        Logger.info "User deleted from evercam. email: #{intercom_email}"
        EvercamMedia.Intercom.delete_user(intercom_email, "email")
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
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "Accept:application/json", "Content-Type": "application/json"]
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
          intercom_user = response.body |> Poison.decode!
          Logger.info "Adding company for email: #{email}, intercom_id: #{intercom_user["id"]}, company_id: #{company_id}"
          intercom_new_user = %{
            id: intercom_user["id"],
            companies: [%{company_id: company_id}]
          }
          |> Poison.encode!
          HTTPoison.post(@intercom_url, intercom_new_user, headers)
        _ -> ""
      end
    end)
  end

  def start_update_status(next_page \\ nil) do
    api_url =
      case next_page do
        url when url in [nil, ""] -> "#{@intercom_url}"
        next_url -> next_url
      end

    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "Accept:application/json"]
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(api_url, headers)
    users = Poison.decode!(body) |> Map.get("users")
    pages = Poison.decode!(body) |> Map.get("pages")
    update_status(users, Map.get(pages, "next"))
  end

  defp update_status([intercom_user | rest], next_url) do
    intercom_email = Map.get(intercom_user, "email")
    user_attributes = Map.get(intercom_user, "custom_attributes")
    intercom_id = Map.get(intercom_user, "id")
    case user_attributes["status"] do
      "Shared-Non-Registered" ->
        case User.by_username_or_email(intercom_email) do
          nil -> Logger.info "Intercom user status is corrected. email: #{intercom_email}"
          %User{} = _user -> update_intercom_user(intercom_id, intercom_email)
        end
      _ -> :noop
    end
    update_status(rest, next_url)
  end
  defp update_status([], nil), do: Logger.info "Users status updated."
  defp update_status([], next_url) do
    Logger.info "Start next page users. URL: #{next_url}"
    start_update_status(next_url)
  end

  defp update_intercom_user(intercom_id, intercom_email) do
    Logger.info "Update statue of intercom user email: #{intercom_email}"
    headers = ["Authorization": "Bearer #{@intercom_token}", "Accept": "Accept:application/json", "Content-Type": "application/json"]

    intercom_new_user = %{
      id: intercom_id,
      email: intercom_email,
      user_id: intercom_email,
      custom_attributes: %{
        status: "Share-Accepted"
      }
    }
    |> Poison.encode!

    HTTPoison.post(@intercom_url, intercom_new_user, headers)
  end
end
