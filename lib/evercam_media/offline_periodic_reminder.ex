defmodule EvercamMedia.OfflinePeriodicReminder do
  @moduledoc """
  Provides functions for getting all offline cameras and send reminder to users

  after 1, 2 and 7 days.
  """
  require Logger

  def offline_cameras_reminder do
    seconds_to_day_before = (60 * 60 * 24) * (-8)
    Calendar.DateTime.now_utc
    |> Calendar.DateTime.advance!(seconds_to_day_before)
    |> Camera.all_offline
    |> Enum.map(&(can_send_reminder &1, &1.alert_emails, &1.last_online_at))
  end

  defp can_send_reminder(_camera, _alert_emails, nil), do: :noop
  defp can_send_reminder(_camera, alert_emails, _last_online_at) when alert_emails in [nil, ""], do: :noop
  defp can_send_reminder(camera, _alert_emails, _last_online_at) do
    current_date = Calendar.DateTime.now!("UTC")
    case Calendar.DateTime.diff(current_date, camera.last_online_at) do
      {:ok, seconds, _, :after} -> do_send_notification(camera, seconds)
      _ -> 0
    end
  end

  defp do_send_notification(camera, seconds) when seconds < 608_500 do
    cond do
      seconds >= 86_400 && seconds < 90_000 ->
        EvercamMedia.UserMailer.camera_offline_reminder(camera.owner, camera, "24 hour")
      seconds >= 172_800 && seconds < 176_400 ->
        EvercamMedia.UserMailer.camera_offline_reminder(camera.owner, camera, "48 hour")
      seconds >= 604_800 && seconds < 608_400 ->
        EvercamMedia.UserMailer.camera_offline_reminder(camera.owner, camera, "7 day (final)")
      true ->
        ""
    end
  end
  defp do_send_notification(_camera, _seconds), do: :noop
end
