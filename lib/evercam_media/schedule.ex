defmodule EvercamMedia.Schedule do
  def scheduled_now?(camera) do
    case camera.cloud_recordings do
      nil -> scheduled_now?(nil, "off", camera.timezone)
      _ -> scheduled_now?(camera.cloud_recordings.schedule, camera.cloud_recordings.status, camera.timezone)
    end
  end

  def scheduled_now?(schedule, status, timezone) do
    case status do
      "on" -> {:ok, true}
      "off" -> {:ok, false}
      "paused" -> {:ok, false}
      _ ->
        timezone =
          case timezone do
            nil -> "UTC"
            _ -> timezone
          end
        now = Calendar.DateTime.now!(timezone)
        scheduled?(schedule, now, timezone)
    end
  end

  def scheduled?(schedule, check_time, timezone \\ nil) do
    check_day = check_time |> Calendar.Date.day_of_week_name
    iterate(schedule[check_day], check_time, timezone)
  end

  defp iterate([head|tail], check_time, timezone) do
    # We expect the head to be in the format "HH:MM-HH:MM"
    head_pattern = ~r/^\d{1,2}:\d{1,2}-\d{1,2}:\d{1,2}$/
    case Regex.match? head_pattern, head do
      true ->
        [from, to] = String.split head, "-"
        [from_hour, from_minute] = String.split from, ":"
        [to_hour, to_minute] = String.split to, ":"

        check_time_unix_timestamp = check_time |> Calendar.DateTime.Format.unix
        from_unix_timestamp = unix_timestamp(from_hour, from_minute, check_time, timezone)
        to_unix_timestamp = unix_timestamp(to_hour, to_minute, check_time, timezone)

        case between(check_time_unix_timestamp, from_unix_timestamp, to_unix_timestamp) do
          true ->
            {:ok, true}
          _ ->
            iterate(tail, check_time, timezone)
        end
      _ ->
        {:error, "Scheduler got an invalid time format: #{inspect(head)}. Expecting Time in the format HH:MM-HH:MM"}
    end

  end

  defp iterate(nil, _check_time, _timezone) do
    {:ok, false}
  end

  defp iterate([], _check_time,  _timezone) do
    {:ok, false}
  end

  defp between(check, start, the_end) do
    check >= start && check <= the_end
  end

  defp unix_timestamp(hours, minutes, date, nil) do
    unix_timestamp(hours, minutes, date, "UTC")
  end

  defp unix_timestamp(hours, minutes, date, timezone) do
    %{year: year, month: month, day: day} = date
    {h, _} = Integer.parse(hours)
    {m, _} = Integer.parse(minutes)
    erl_date_time = {{year, month, day}, {h, m, 0}}
    case Calendar.DateTime.from_erl(erl_date_time, timezone) do
      {:ok, datetime} -> datetime |> Calendar.DateTime.Format.unix
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd |> Calendar.DateTime.Format.unix
      _ -> raise "Timezone conversion error"
    end
  end
end
