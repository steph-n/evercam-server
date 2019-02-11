defmodule EvercamMediaWeb.UserController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMediaWeb.LogView
  alias EvercamMedia.Repo
  alias EvercamMedia.Util
  alias EvercamMedia.Intercom
  require Logger

  def swagger_definitions do
    %{
      User: swagger_schema do
        title "User"
        description ""
        properties do
          id :integer, ""
          firstname :string, "", format: "text"
          lastname :string, "", format: "text"
          username :string, "", format: "text"
          telegram_username :string, "", format: "text"
          password :string, "", format: "text"
          country_id :integer, ""
          email :string, "", format: "text"
          reset_token :string, "", format: "text"
          token_expires_at :string, "", format: "timestamp"
          api_id :string, "", format: "text"
          api_key :string, "", format: "text"
          is_admin :boolean, "", default: false
          stripe_customer_id :string, "", format: "text"
          billing_id :string, "", format: "text"
          vat_number :string, "", format: "text"
          payment_method :integer, ""
          insight_id :string, "", format: "text"
          created_at :string, "", format: "timestamp"
          updated_at :string, "", format: "timestamp"
        end
      end
    }
  end

  swagger_path :get do
    get "/users/{id}"
    summary "Returns the single user's profile details."
    parameters do
      id :path, :string, "Username/email of the existing user.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Users"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "User does not exist"
  end

  def get(conn, params) do
    %{assigns: %{version: version}} = conn
    caller = conn.assigns[:current_user]
    user =
      params["id"]
      |> String.replace_trailing(".json", "")
      |> User.by_username_or_email

    cond do
      !user ->
        render_error(conn, 404, "User does not exist.")
      !caller || !Permission.User.can_view?(caller, user) ->
        render_error(conn, 401, %{message: "Unauthorized."})
      true -> render(conn, "show.#{version}.json", %{user: user})
    end
  end

  swagger_path :credentials do
    get "/users/{id}/credentials"
    summary "Returns API credentials of given user."
    parameters do
      id :path, :string, "Username/email of the user being requested.", required: true
      password :query, :string, "", required: true
    end
    tag "Users"
    response 200, "Success"
    response 400, "Invalid password"
    response 404, "User does not exit"
  end

  def credentials(conn, %{"id" => username} = params) do
    user =
      params["id"]
      |> String.replace_trailing(".json", "")
      |> User.by_username_or_email

    with :ok <- ensure_user_exists(user, username, conn),
         :ok <- password(params["password"], user, conn)
    do
      update_last_login_and_log(Application.get_env(:evercam_media, :run_spawn), conn, user, params)
      render(conn, "credentials.json", %{user: user})
    end
  end

  swagger_path :credentialstelegram do
    get "/users/telegram/{id}/credentials"
    summary "Returns API credentials of given telegram user."
    parameters do
      id :path, :string, "Telegram username of the user being requested.", required: true
    end
    tag "Users"
    response 200, "Success"
    response 400, "Invalid telegram_username"
    response 404, "User does not exit"
  end

  def credentialstelegram(conn, %{"id" => telegram_username}) do
    %{assigns: %{version: version}} = conn
    caller = conn.assigns[:current_user]
    user =
      telegram_username
      |> String.replace_trailing(".json", "")
      |> User.by_telegram_username

    cond do
      !user ->
        render_error(conn, 404, %{message: "User does not exist."})
      !caller || !Permission.User.can_view?(caller, user) ->
        render_error(conn, 401, %{message: "Unauthorized."})
      true ->
        conn
        |> render("show.#{version}.json", %{user: user})
    end
  end

  swagger_path :create do
    post "/users"
    summary "User signup."
    parameters do
      firstname :query, :string, "", required: true
      lastname :query, :string, "", required: true
      username :query, :string, "", required: true
      telegram_username :query, :string, ""
      email :query, :string, "", required: true
      password :query, :string, "", required: true
      token :query, :string, "Please use your token according to your platform (WEB, IOS, ANDROID)", required: true
    end
    tag "Users"
    response 201, "Success"
    response 400, "Invalid token | email or password has already been taken"
  end

  def create(conn, params) do
    %{assigns: %{version: version}} = conn
    with :ok <- ensure_application(conn, params["token"]),
         {:ok, country_id} <- ensure_country(params["country"], conn)
    do
      requester_ip = user_request_ip(conn, params["requester_ip"])
      user_agent = get_user_agent(conn)
      share_request_key = params["share_request_key"]
      api_id = UUID.uuid4(:hex) |> String.slice(0..7)
      api_key = UUID.uuid4(:hex)

      params =
        params
        |> add_parameter("country_id", country_id)
        |> add_parameter("api_id", api_id)
        |> add_parameter("api_key", api_key)
        |> add_parameter("telegram_username", params["telegram_username"])
        |> Map.delete("country")

      params =
        case has_share_request_key?(share_request_key) do
          true ->
            Map.merge(params, %{"confirmed_at" => Calendar.DateTime.now_utc})
            |> Map.delete("share_request_key")
          false ->
            Map.delete(params, "share_request_key")
        end

      changeset = User.changeset(%User{}, params)
      case Repo.insert(changeset) do
        {:ok, user} ->
          request_hex_code = UUID.uuid4(:hex)
          token = Ecto.build_assoc(user, :access_tokens, is_revoked: false,
            request: request_hex_code |> String.slice(0..31))

          case Repo.insert(token) do
            {:ok, token} -> {:success, user, token}
            {:error, changeset} -> {:invalid_token, changeset}
          end
          if !has_share_request_key?(share_request_key) do
            created_at =
              user.created_at
              |> Calendar.Strftime.strftime!("%Y-%m-%d %T UTC")

            code =
              :crypto.hash(:sha, user.username <> created_at)
              |> Base.encode16
              |> String.downcase

            share_default_camera(user)
            EvercamMedia.UserMailer.confirm(user, code)
            Intercom.intercom_activity(Application.get_env(:evercam_media, :create_intercom_user), user, user_agent, requester_ip)
          else
            share_request = CameraShareRequest.by_key_and_status(share_request_key)
            create_share_for_request(share_request, user, conn)
            Intercom.update_user(Application.get_env(:evercam_media, :create_intercom_user), user, user_agent, requester_ip)
          end
          share_requests = CameraShareRequest.by_email(user.email)
          multiple_share_create(share_requests, user, conn)
          Logger.info "[POST v1/users] [#{user_agent}] [#{requester_ip}] [#{user.username}] [#{user.email}] [#{params["token"]}]"
          conn
          |> put_status(:created)
          |> render("show.#{version}.json", %{user: user |> Repo.preload(:country, force: true)})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def password_reset_token(conn, %{"id" => email} = params) do
    email = String.downcase(email)

    with {:ok, user} <- user_exists(conn, email)
    do
      user_params =
        case validate_reset_token(user.reset_token, user.token_expires_at) do
          true -> %{reset_token: user.reset_token, token_expires_at: user.token_expires_at}
          _ ->
            expires =
              Calendar.DateTime.now_utc
              |> Calendar.DateTime.advance!(60 * 60 * 24)
            %{reset_token: UUID.uuid4(:hex), token_expires_at: expires}
        end

      changeset = User.changeset(user, user_params)
      case Repo.update(changeset) do
        {:ok, updated_user} ->
          extra =
            %{agent: get_user_agent(conn, params["agent"])}
            |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
          CameraActivity.log_activity(updated_user, %{id: 0, exid: ""}, "requested for password reset", extra)
          EvercamMedia.UserMailer.password_reset_request(updated_user)
          conn |> put_status(200) |> json(%{message: "We’ve sent you an email with instructions for changing your password."})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def password_update(conn, %{"id" => email} = params) do
    email = String.downcase(email)
    with {:ok, user} <- user_exists(conn, email),
         :ok <- is_valid_token(conn, params["token"], user.reset_token),
         :ok <- is_expired_token(conn, user.token_expires_at)
    do
      user_params = %{reset_token: "", token_expires_at: Calendar.DateTime.now_utc, password: params["password"]}
      changeset = User.changeset(user, user_params)
      case Repo.update(changeset) do
        {:ok, updated_user} ->
          extra =
            %{agent: get_user_agent(conn, params["agent"])}
            |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
          CameraActivity.log_activity(updated_user, %{id: 0, exid: ""}, "password changed", extra)
          conn |> put_status(200) |> json(%{message: "Password changed successfully."})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :user_exist do
    post "/users/exist/{input}"
    summary "Check the existence of the user."
    parameters do
      input :path, :string, "Username/email of the user being requested.", required: true
    end
    tag "Users"
    response 201, "Success"
    response 404, "User does not exit"
  end

  def user_exist(conn, %{"input" => input} = _params) do
    with %User{} <- User.by_username_or_email(input) do
      conn
      |> put_status(201)
      |> json(%{user: true})
    else
      nil ->
        conn
        |> put_status(404)
        |> json(%{user: false})
    end
  end

  def ensure_application(conn, token) when token in [nil, ""], do: render_error(conn, 400, "Invalid token.")
  def ensure_application(conn, token) do
    cond do
       System.get_env["WEB_APP"] == token -> :ok
       System.get_env["IOS_APP"] == token -> :ok
       System.get_env["ANDROID_APP"] == token -> :ok
       true -> render_error(conn, 400, "Invalid token.")
    end
  end

  swagger_path :update do
    patch "/users/{id}"
    summary "Updates full or partial data on your existing user account."
    parameters do
      id :path, :string, "Username/email of the existing user.", required: true
      firstname :query, :string, ""
      lastname :query, :string, ""
      username :query, :string, ""
      telegram_username :query, :string, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Users"
    response 201, "Success"
    response 400, "Invalid token | email or password has already been taken"
  end

  def update(conn, %{"id" => username} = params) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    requester_ip = user_request_ip(conn, params["requester_ip"])
    user_agent = get_user_agent(conn, params["agent"])
    username = username |> String.replace_trailing(".json", "")
    old_user = User.by_username_or_email(username)

    with :ok <- ensure_user_exists(old_user, username, conn),
         :ok <- ensure_can_view(current_user, old_user, conn),
         {:ok, country_id} <- ensure_country(params["country"], conn)
    do
      user_params =
        %{}
        |> add_parameter(:firstname, params["firstname"])
        |> add_parameter(:lastname, params["lastname"])
        |> add_parameter(:email, params["email"])
        |> add_parameter(:telegram_username, params["telegram_username"])
        |> add_parameter(:country_id, country_id)

      changeset = User.changeset(old_user, user_params)
      case Repo.update(changeset) do
        {:ok, new_user} ->
          updated_user = new_user |> Repo.preload(:country, force: true)
          insert_activity(old_user, updated_user, requester_ip, user_agent, params["u_country"], params["u_country_code"])
          Intercom.update_intercom_user(Application.get_env(:evercam_media, :create_intercom_user), updated_user, username, user_agent, requester_ip)
          render(conn, "show.#{version}.json", %{user: updated_user})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :delete do
    delete "/users/{id}"
    summary "Delete your account, any cameras you own and all stored media."
    parameters do
      id :path, :string, "Username/email of the existing user.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Users"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "User does not exist"
  end

  def delete(conn, %{"id" => username}) do
    current_user = conn.assigns[:current_user]
    user =
      username
      |> String.replace_trailing(".json", "")
      |> User.by_username_or_email

    with :ok <- ensure_user_exists(user, username, conn),
         :ok <- ensure_can_view(current_user, user, conn)
    do
      spawn(fn -> delete_user(user) end)
      json(conn, %{})
    end
  end

  swagger_path :user_activities do
    get "/users/{id}/activities"
    summary "Returns the logs of given user."
    parameters do
      id :path, :string, "Username/email of the user.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Users"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "User does not exist"
  end

  def user_activities(conn, params) do
    %{assigns: %{version: version}} = conn
    current_user = conn.assigns[:current_user]
    from = parse_from(params["from"])
    to = parse_to(params["to"])
    types = parse_types(params["types"])

    with :ok <- authorized(conn, current_user)
    do
      user = current_user |> Repo.preload(:access_tokens, force: true)
      user_logs = CameraActivity.for_a_user(user.access_tokens.id, from, to, types)

      conn
      |> put_view(LogView)
      |> render("user_logs.#{version}.json", %{user_logs: user_logs})
    end
  end

  defp delete_user(user) do
    delete_user_camera_compares(user)
    CameraShare.delete_by_user(user.id)
    CameraShareRequest.delete_by_user_id(user.id)
    Camera.delete_by_owner(user.id)
    User.delete_by_id(user.id)
    User.invalidate_auth(user.api_id, user.api_key)
    Camera.invalidate_user(user)
    User.invalidate_share_users(user)
    Intercom.delete_user(user.username)
  end

  defp delete_user_camera_compares(user) do
    Camera.for(user, false)
    |> Enum.map(fn(cam) -> cam.id end)
    |> Enum.each(fn(id) -> Compare.delete_by_camera(id) end)
  end

  defp user_exists(conn, email) do
    case User.by_username_or_email(email) do
      nil -> render_error(conn, 404, "User not found.")
      %User{} = user -> {:ok, user}
    end
  end

  defp validate_reset_token(token, _token_expires_at) when token in [nil, ""], do: false
  defp validate_reset_token(_token, token_expires_at) when token_expires_at in [nil, ""], do: false
  defp validate_reset_token(_token, token_expires_at) do
    current_date = Calendar.DateTime.now_utc

    case Calendar.DateTime.diff(current_date, token_expires_at) do
      {:ok, _, _, :before} -> true
      _ -> false
    end
  end

  def is_valid_token(conn, param_token, token) do
    case (param_token == token) do
      true -> :ok
      false -> render_error(conn, 404, "Invalid token.")
    end
  end

  def is_expired_token(conn, token_expires_at) when token_expires_at in [nil, ""], do: render_error(conn, 404, "your password reset token has been expired.")
  def is_expired_token(conn, token_expires_at) do
    case Calendar.DateTime.diff(token_expires_at, Calendar.DateTime.now_utc) do
      {:ok, _, _, :before} -> render_error(conn, 404, "your password reset token has been expired.")
      _ -> :ok
    end
  end

  defp insert_activity(caller, updated_user, ip, agent, country, country_code) do
    spawn(fn ->
      camera = %{id: 0, exid: ""}
      extra = %{
        agent: agent,
        user_settings: %{ old: set_settings(caller), new: set_settings(updated_user) }
      }
      |> Map.merge(get_requester_Country(ip, country, country_code))
      CameraActivity.log_activity(caller, camera, "user edited", extra)
    end)
  end

  defp set_settings(user) do
    %{
      firstname: user.firstname,
      lastname: user.lastname,
      username: user.username,
      email: user.email,
      country: Util.deep_get(user, [:country, :name], "")
    }
  end

  defp add_parameter(params, _key, nil), do: params
  defp add_parameter(params, key, value) do
    Map.put(params, key, value)
  end

  defp ensure_user_exists(nil, username, conn) do
    render_error(conn, 404, "User '#{username}' does not exist.")
  end
  defp ensure_user_exists(_user, _id, _conn), do: :ok

  defp ensure_can_view(current_user, user, conn) do
    if current_user && Permission.User.can_view?(current_user, user) do
      :ok
    else
      render_error(conn, 403, "Unauthorized.")
    end
  end

  defp password(password, user, conn) do
    if Comeonin.Bcrypt.checkpw(password, user.password) do
      :ok
    else
      render_error(conn, 400, "Invalid password.")
    end
  end

  defp ensure_country(country_id, _conn) when country_id in [nil, ""], do: {:ok, nil}
  defp ensure_country(country_id, conn) do
    country = Country.by_iso3166(country_id)
    case country do
      nil -> render_error(conn, 400, "Country isn't valid!")
      _ -> {:ok, country.id}
    end
  end

  defp update_last_login_and_log(true, conn, user, params) do
    spawn(fn ->
      changeset = User.changeset(user, %{"last_login_at" => Calendar.DateTime.to_erl(Calendar.DateTime.now_utc)})
      Repo.update(changeset)

      extra =
        %{ agent: get_user_agent(conn, params["agent"]) }
        |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
      CameraActivity.log_activity(user, %{ id: 0, exid: "" }, "login", extra)
    end)
  end
  defp update_last_login_and_log(_mode, _conn, _user, _params), do: :noop

  defp has_share_request_key?(value) when value in [nil, ""], do: false
  defp has_share_request_key?(_value), do: true

  defp share_default_camera(user) do
    evercam_user = User.by_username("evercam")
    remembrance_camera = Camera.get_remembrance_camera
    rights = CameraShare.get_rights("public", evercam_user, remembrance_camera)
    message = "Default camera shared with newly created user."

    CameraShare.create_share(remembrance_camera, user, evercam_user, rights, message, "public")
  end

  defp create_share_for_request(nil, _user, conn), do: render_error(conn, 400, "Camera share request does not exist.")
  defp create_share_for_request(share_request, user, conn) do
    if share_request.email != user.email do
      render_error(conn, 400, "The email address specified does not match the share request email.")
    else
      share_request
      |> CameraShareRequest.changeset(%{status: 1})
      |> Repo.update
      |> case do
        {:ok, share_request} ->
          CameraShare.create_share(share_request.camera, user, share_request.user, share_request.rights, share_request.message)
          Camera.invalidate_camera(share_request.camera)
          accepted_request_notification(share_request)
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  defp multiple_share_create(nil, _user, _conn), do: Logger.info "No share request found."
  defp multiple_share_create(share_requests, user, conn) do
    Enum.each(share_requests, fn(share_request) -> create_share_for_request(share_request, user, conn) end)
  end

  defp parse_to(to) when to in [nil, ""], do: Calendar.DateTime.now_utc
  defp parse_to(to), do: to |> Calendar.DateTime.Parse.unix!

  defp parse_from(from) when from in [nil, ""] do
    Calendar.DateTime.Parse.rfc3339_utc("2014-01-01T14:00:00Z")
    |> elem(1)
  end
  defp parse_from(from), do: from |> Calendar.DateTime.Parse.unix!

  defp parse_types(types) when types in [nil, ""], do: nil
  defp parse_types(types), do: types |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp accepted_request_notification(share_request) do
    try do
      Task.start(fn ->
        EvercamMedia.UserMailer.accepted_share_request_notification(share_request.user, share_request.camera, share_request.email)
      end)
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
    end
  end

  defp authorized(conn, nil), do: render_error(conn, 401, "Unauthorized.")
  defp authorized(_conn, _current_user), do: :ok
end
