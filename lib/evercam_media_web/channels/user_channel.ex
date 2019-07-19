defmodule EvercamMediaWeb.UserChannel do
  use Phoenix.Channel
  alias EvercamMedia.Util

  def join("users:" <> username, _params, socket) do
    caller_username = Util.deep_get(socket, [:assigns, :current_user, :username], "")

    case String.equivalent?(username, caller_username) do
      true ->
        send(self(), {:after_join, username})
        {:ok, socket}
      _ -> {:error, "Unauthorized."}
    end
  end

  def handle_info({:after_join, _username}, socket) do
    {:noreply, socket}
  end
end
