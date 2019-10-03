defmodule EvercamMedia.Validation.CloudRecording do
  def validate_params(params) do
    with :ok <- validate(:frequency, params["frequency"]),
         :ok <- validate(:storage_duration, params["storage_duration"]),
         :ok <- validate(:status, params["status"]),
         :ok <- validate(:schedule, params["schedule"]),
         do: :ok
  end

  defp validate(key, value) when value in [nil, ""], do: invalid(key)

  defp validate(:status, "on"), do: :ok
  defp validate(:status, "off"), do: :ok
  defp validate(:status, "paused"), do: :ok
  defp validate(:status, "on-scheduled"), do: :ok
  defp validate(:status = key, _value), do: invalid(key)

  defp validate(:schedule = key, value) do
    case Jason.decode(value) do
      {:ok, json} -> valid_schedule(key, json)
      {:error, _error} -> invalid(key)
    end
  end

  defp validate(_key, value) when is_integer(value), do: :ok
  defp validate(key, value) when is_bitstring(value), do: validate(key, to_integer(value))
  defp validate(key, _value), do: invalid(key)

  defp invalid(key), do: {:invalid, "The parameter '#{key}' isn't valid."}

  defp to_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> :error
    end
  end

  defp valid_schedule(key, json) do
    case is_map(json) do
      true -> :ok
      false -> invalid(key)
    end
  end
end
