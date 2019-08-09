defmodule EvercamMediaWeb.JwtAuthPlug do
  import Plug.Conn
  alias EvercamMediaWeb.JwtAuthToken

  def init(opts), do: opts

  def call(conn, _opts) do
    case JwtAuthToken.decode(jwt_from_map, public_key) do
      { :success, %{token: token, claims: claims} } ->
        conn |> success(claims)
      { :error, error } ->
        conn |> forbidden
    end
  end

  defp public_key do
    # your public key string that you read from a PEM file or stored in an env var or fetched from an endpoint
  end

  defp success(conn, token_payload) do
    assign(conn, :claims, token_payload.claims)
    |> assign(:jwt, token_payload.token)
  end

  defp jwt_from_cookie(conn) do
    conn
    |> Plug.Conn.get_req_header("authorization")
    |> List.first
    |> Plug.Conn.Cookies.decode
    |> token_from_map(conn)
  end

  defp token_from_map(%{"session_jwt" => jwt}, _conn), do: jwt

  defp token_from_map(_cookie_map, conn) do
    conn
    |> forbidden
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(401, Poison.encode!(%{message: "Invalid API keys"}))
    |> send_resp
    |> halt
  end
end
