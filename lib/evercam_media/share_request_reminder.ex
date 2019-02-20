defmodule EvercamMedia.ShareRequestReminder do
  @moduledoc """
  Provides functions for getting all pending shared requests and send notification

  for all those requests which are older than 7 days.
  """

  alias Evercam.Repo
  require Logger

  def check_share_requests do
    seconds_to_day_before = (60 * 60 * 24) * (-22)
    Calendar.DateTime.now_utc
    |> Calendar.DateTime.advance!(seconds_to_day_before)
    |> CameraShareRequest.get_all_pending_requests
    |> Enum.map(&(send_reminder &1))
  end

  defp send_reminder(share_request) do
    current_date = Calendar.DateTime.now!("UTC")
    camera_time =
      Calendar.DateTime.now!("UTC")
      |> Calendar.DateTime.shift_zone!(Camera.get_timezone(share_request.camera))
      |> Calendar.DateTime.to_erl
      |> elem(1)
    {hour, _minute, _second} = camera_time
    if hour == 9 do
      case Calendar.DateTime.diff(current_date, share_request.created_at) do
        {:ok, total_seconds, _, :after} ->
          can_send_reminder(share_request, current_date, total_seconds)
        _ -> 0
      end
    end
  end

  defp can_send_reminder(share_request, current_date, total_seconds) when total_seconds < 1_814_400 do
    case Calendar.DateTime.diff(current_date, share_request.updated_at) do
      {:ok, seconds, _, :after} -> send_notification(share_request, seconds)
      _ -> 0
    end
  end
  defp can_send_reminder(_share_request, _current_date, _total_seconds), do: :noop

  # 7 days seconds 604800
  defp send_notification(share_request, seconds) when seconds > 604_800 do
    send_email_notification(share_request.user, share_request.camera, share_request.email, share_request.message, share_request.key)
    share_request
    |> CameraShareRequest.update_changeset(%{updated_at: Calendar.DateTime.to_erl(Calendar.DateTime.now_utc)})
    |> Repo.update
  end
  defp send_notification(_share_request, _seconds), do: :noop

  defp send_email_notification(user, camera, to_email, message, share_request_key) do
    try do
      Task.start(fn ->
        EvercamMedia.UserMailer.camera_share_request_notification(user, camera, to_email, message, share_request_key)
      end)
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
    end
  end
end
