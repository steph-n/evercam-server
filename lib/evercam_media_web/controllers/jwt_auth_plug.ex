defmodule EvercamMediaWeb.JwtAuthPlug do
  import Plug.Conn
  alias EvercamMediaWeb.JwtAuthToken

  def init(opts), do: opts

  def call(conn, _opts) do
    jwt_string = jwt_from_cookie(conn)
    case JwtAuthToken.verify_and_validate(jwt_string) do
      { :ok, claims } ->
        user = User.by_username_or_email(claims["user_id"])
        conn |> assign(:current_user, user)
      { :error, error } ->
        conn |> forbidden
    end
  end

  defp jwt_from_cookie(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> List.first
    |> String.replace_leading("Bearer ", "")
    |> to_string
  end

  defp success(conn, token_payload) do
    assign(conn, :claims, token_payload.claims)
    |> assign(:jwt, token_payload.token)
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(401, Poison.encode!(%{message: "Invalid API keys"}))
    |> send_resp
    |> halt
  end
end
