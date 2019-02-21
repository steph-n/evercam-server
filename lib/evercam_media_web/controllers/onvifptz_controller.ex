defmodule EvercamMediaWeb.ONVIFPTZController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMedia.ONVIFPTZ

  swagger_path :status do
    get "/cameras/{id}/ptz/status"
    summary "Returns ptz status of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def status(conn, _params) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.get_status("Profile_1") |> respond_default(conn)
  end

  swagger_path :nodes do
    get "/cameras/{id}/ptz/nodes"
    summary "Returns ptz nodes of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def nodes(conn, _params) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.get_nodes |> respond_default(conn)
  end

  swagger_path :configurations do
    get "/cameras/{id}/ptz/configurations"
    summary "Returns ptz configurations of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def configurations(conn, _params) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.get_configurations |> respond_default(conn)
  end

  swagger_path :presets do
    get "/cameras/{id}/ptz/presets"
    summary "Returns all ptz presets of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def presets(conn, _params) do
    conn.assigns.onvif_access_info
    |> ONVIFPTZ.get_presets("Profile_1")
    |> case do
      {:ok, response} -> respond_default({:ok, response}, conn)
      _ -> respond_default({:ok, %{"Presets" => []}}, conn)
    end
  end

  swagger_path :stop do
    get "/cameras/{id}/ptz/continuous/stop"
    summary "Stop the ptz of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 200, "Success"
    response 401, "Invalid API keys"
  end

  def stop(conn, _params) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.stop("Profile_1") |> respond(conn)
  end

  swagger_path :home do
    post "/cameras/{id}/ptz/home"
    summary "Returns PTZ home of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def home(conn, _params) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.goto_home_position("Profile_1") |> respond(conn)
  end

  swagger_path :sethome do
    post "/cameras/{id}/ptz/home/set"
    summary "Set ptz home of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def sethome(conn, _params) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.set_home_position("Profile_1") |> respond(conn)
  end

  swagger_path :gotopreset do
    post "/cameras/{id}/ptz/presets/go/{preset_token}"
    summary "Go to specific preset of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      preset_token :path, :integer, "Unique token number of the preset.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def gotopreset(conn, %{"preset_token" => token}) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.goto_preset("Profile_1", token) |> respond(conn)
  end

  swagger_path :setpreset do
    post "/cameras/{id}/ptz/presets/{preset_token}/set"
    summary "Set the view of the camera to given preset."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      preset_token :path, :integer, "Unique token number of the preset.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def setpreset(conn, %{"preset_token" => token}) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.set_preset("Profile_1", "", token) |> respond(conn)
  end

  swagger_path :createpreset do
    post "/cameras/{id}/ptz/presets/create"
    summary "Create new ptz preset of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      preset_name :query, :string, ""
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def createpreset(conn, %{"preset_name" => name}) do
    conn.assigns.onvif_access_info |> ONVIFPTZ.set_preset("Profile_1", name) |> respond(conn)
  end

  swagger_path :continuousmove do
    post "/cameras/{id}/ptz/continuous/start/{direction}"
    summary "Move the camera to given direction."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      direction :path, :string, "", enum: ["left", "right", "up", "down"], required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def continuousmove(conn, %{"direction" => direction}) do
    velocity =
      case direction do
        "left" -> [x: -0.1, y: 0.0]
        "right" -> [x: 0.1, y: 0.0]
        "up" -> [x: 0.0, y: 0.1]
        "down" -> [x: 0.0, y: -0.1]
        _ -> [x: 0.0, y: 0.0]
      end
    conn.assigns.onvif_access_info |> ONVIFPTZ.continuous_move("Profile_1", velocity) |> respond(conn)
  end

  swagger_path :continuouszoom do
    post "/cameras/{id}/ptz/continuous/zoom/{mode}"
    summary "Zoom in/out of the camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      mode :path, :string, "", enum: ["in", "out"], required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def continuouszoom(conn, %{"mode" => mode}) do
    velocity =
      case mode do
        "in" -> [zoom: 0.01]
        "out" -> [zoom: -0.01]
        _ -> [zoom: 0.0]
      end
    conn.assigns.onvif_access_info |> ONVIFPTZ.continuous_move("Profile_1", velocity) |> respond(conn)
  end

  swagger_path :relativemove do
    post "/cameras/{id}/ptz/relative"
    summary "Relative move of the camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      left :query, :integer, "Left move, for example 4"
      right :query, :integer, "Right move, for example 4"
      up :query, :integer, "Up move, for example 4"
      down :query, :integer, "Down move, for example 4"
      zoom :query, :integer, "Zoom, for example 1"
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Onvif"
    response 201, "Success"
    response 401, "Invalid API keys"
  end

  def relativemove(conn, params) do
    left = Map.get(params, "left", "0") |> String.to_integer
    right = Map.get(params, "right", "0") |> String.to_integer
    up = Map.get(params, "up", "0") |> String.to_integer
    down = Map.get(params, "down", "0") |> String.to_integer
    zoom = Map.get(params, "zoom", "0") |> String.to_integer
    x =
      cond do
        right > left -> right
        true -> -left
      end
    y =
      cond do
        down > up -> down
        true -> -up
      end
    conn.assigns.onvif_access_info |> ONVIFPTZ.relative_move("Profile_1", [x: x / 100.0, y: y / 100.0, zoom: zoom / 100.0]) |> respond(conn)
  end

  defp respond({:ok, response}, conn) do
    conn
    |> put_status(:created)
    |> json(response)
  end

  defp respond({:error, code, response}, conn) do
    conn
    |> put_status(code)
    |> json(response)
  end

  defp respond_default({:ok, response}, conn) do
    conn
    |> json(response)
  end
end
