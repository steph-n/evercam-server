defmodule EvercamMediaWeb.ThumbnailChannel do
  use Phoenix.Channel
  alias EvercamMedia.Util

  def join("thumbnail:render", _auth_msg, socket) do
    user = Util.deep_get(socket, [:assigns, :current_user], nil)

    case user do
      nil -> {:error, "Unauthorized."}
      _ ->
        send(self(), {:after_join})
        {:ok, socket}
    end
  end

  def handle_in("thumbnail", %{"body" => body}, socket) do
    camera = Camera.get_full(body)
    spawn(fn -> EvercamMediaWeb.SnapshotController.update_thumbnail(true, camera) end)

    image =
      case EvercamMedia.Snapshot.Storage.thumbnail_load(body) do
        {:ok, timestamp, image} -> image
        {:error, image} -> image
      end
    EvercamMediaWeb.Endpoint.broadcast("thumbnail:render",
      "thumbnail", %{camera_exid: camera.exid, image: Base.encode64(image)})
    {:noreply, socket}
  end

  def terminate(_msg, socket) do
    {:noreply, socket}
  end

  def handle_info({:after_join}, socket) do
    {:noreply, socket}
  end
end
