defmodule EvercamMediaWeb.ONVIFAccessPlug do
  import Plug.Conn

  def init(_opts) do
  end

  def call(conn, _) do
    access_info =
      case conn.query_params do
        %{"auth" => _auth, "url" => _url} -> conn.query_params
        %{"id" => id} -> Camera.get_camera_info(id)
        _ -> Camera.get_camera_info(conn.params["id"])
      end

    parameters =
      conn.query_params
      |> Enum.filter(fn({key, _value}) -> key != "id" and key != "url" and key != "auth" end)
      |> Enum.reduce("", fn({key, value}, acc) -> "#{acc}<#{key}>#{value}</#{key}>" end)

    with %User{} <- User.get_by_api_keys(conn.query_params["api_id"], conn.query_params["api_key"]) do
      conn
      |> assign(:onvif_parameters, parameters)
      |> assign(:onvif_access_info, access_info)
    else
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> resp(401, Jason.encode!(%{message: "Invalid API keys"}))
        |> send_resp
        |> halt
    end
  end
end
