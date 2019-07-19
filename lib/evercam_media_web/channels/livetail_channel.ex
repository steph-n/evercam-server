defmodule EvercamMediaWeb.LivetailChannel do
  use Phoenix.Channel
  alias EvercamMedia.Util

  def join("livetail:" <> camera_exid, _auth_msg, socket) do
    camera = Camera.get_full(camera_exid)
    user = Util.deep_get(socket, [:assigns, :current_user], nil)

    case Permission.Camera.can_list?(user, camera) do
      true ->
        send(self(), {:after_join, camera_exid})
        {:ok, socket}
      _ -> {:error, "Unauthorized."}
    end
  end

  def handle_info({:after_join, _camera_exid}, socket) do
    {:noreply, socket}
  end
end
