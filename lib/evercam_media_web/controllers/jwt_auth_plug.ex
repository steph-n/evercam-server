defmodule EvercamMediaWeb.JwtAuthPlug do
  import Plug.Conn
  alias EvercamMediaWeb.JwtAuthToken

  def init(_opts) do
  end

  def call(conn, _opts) do
    jwt_string = jwt_from_cookie(conn)
    jwt_string
    |> AccessToken.by_request_token
    |> handle_response(conn, jwt_string)
  end

  defp handle_response(nil, conn, jwt_string), do: conn |> forbidden(%{message: "Token '#{jwt_string}' is revoked."})
  defp handle_response({:ok, claims}, conn, _), do: conn |> assign(:current_user, User.by_username_or_email(claims["user_id"]))
  defp handle_response({:error, error}, conn, _), do: conn |> forbidden(error)
  defp handle_response(_, conn, jwt_string), do: JwtAuthToken.verify_and_validate(jwt_string) |> handle_response(conn, jwt_string)

  defp jwt_from_cookie(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> List.first
    |> String.replace_leading("Bearer ", "")
    |> to_string
  end

  defp forbidden(conn, error) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(401, Poison.encode!(%{message: error[:message]}))
    |> send_resp
    |> halt
  end
end
