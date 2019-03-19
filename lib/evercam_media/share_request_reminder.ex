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
        {:ok, total_seconds, _, :after} -> can_send_reminder(share_request, current_date, total_seconds)
        _ -> 0
      end
    end
  end

  defp can_send_reminder(share_request, current_date, total_seconds) when total_seconds < 1_846_805 do
    case Calendar.DateTime.diff(current_date, share_request.updated_at) do
      {:ok, seconds, _, :after} -> send_notification(share_request, seconds)
      _ -> 0
    end
  end
  defp can_send_reminder(_share_request, _current_date, _total_seconds), do: :noop

  # Send reminder after 1, 7 and 21 days
  defp send_notification(share_request, seconds) do
    cond do
      seconds >= 115_200 && seconds < 118_800 ->
        Logger.debug "1 Day reminder."
      seconds >= 633_600 && seconds < 637_200 ->
        send_email_notification(share_request)
      seconds >= 1_846_800 && seconds < 1_843_200 ->
        send_email_notification(share_request)
      true -> :noop
    end
  end

  defp send_email_notification(share_request) do
    try do
      Task.start(fn ->
        EvercamMedia.UserMailer.camera_share_request_notification(share_request.user, share_request.camera, share_request.email, share_request.message, share_request.key)
      end)
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
    end
    share_request
    |> CameraShareRequest.update_changeset(%{updated_at: Calendar.DateTime.to_erl(Calendar.DateTime.now_utc)})
    |> Repo.update
  end
end
