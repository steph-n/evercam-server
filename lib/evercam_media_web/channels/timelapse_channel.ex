defmodule EvercamMediaWeb.TimelapseChannel do
    use Phoenix.Channel
    alias EvercamMedia.Util
    alias EvercamMedia.Snapshot.Storage
  
    def join("timelapse:" <> session_id, _auth_msg, socket) do
      user = Util.deep_get(socket, [:assigns, :current_user], nil)
  
      case user do
        nil -> {:error, "Unauthorized."}
        _ ->
          send(self(), {:after_join, session_id})
          {:ok, socket}
      end
    end
  
    def handle_in("get-thumbnail", %{"from" => from_datetime, "to" => to_datetime, "id" => camera_exid, "session_id" => session_id}, socket) do
      camera = Camera.get_full(camera_exid)
      timezone = Camera.get_timezone(camera)
      start_date =
        from_datetime
        |> NaiveDateTime.from_iso8601!
        |> Calendar.DateTime.from_naive(timezone)
        |> elem(1)
        |> Calendar.DateTime.to_erl
        |> Calendar.DateTime.from_erl!(timezone)
  
      end_date =
        to_datetime
        |> NaiveDateTime.from_iso8601!
        |> Calendar.DateTime.from_naive(timezone)
        |> elem(1)
        |> Calendar.DateTime.to_erl
        |> Calendar.DateTime.from_erl!(timezone)
      interval =
        case Calendar.DateTime.diff(end_date, start_date) do
          {:ok, seconds, _, :after} -> seconds / 10 |> round
          _ -> 1
        end
      1..11 |> Enum.reduce(start_date, fn _i, acc ->
        case Storage.hour(camera_exid, acc, :v2, timezone) do
          [] ->
            IO.inspect "Snapshot not found"
          _ ->
            image = Storage.nearest(camera_exid, acc |> Calendar.DateTime.Format.unix, :v2, timezone) |> List.first
            EvercamMediaWeb.Endpoint.broadcast("timelapse:" <> session_id, "preview-thumbnail", %{image: image.data})
        end
        acc |> Calendar.DateTime.to_erl |> Calendar.DateTime.from_erl(timezone, {123456, 6}) |> ambiguous_handle |> Calendar.DateTime.add!(interval)
      end)
      {:noreply, socket}
    end
  
    defp ambiguous_handle(value) do
      case value do
        {:ok, datetime} -> datetime
        {:ambiguous, datetime} -> datetime.possible_date_times |> hd
      end
      end
  
    def terminate(_msg, socket) do
      {:noreply, socket}
    end
  
    def handle_info({:after_join, _session_id}, socket) do
      {:noreply, socket}
    end
  end