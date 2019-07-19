defmodule EvercamMedia.Validation.Log do
  import String, only: [to_integer: 1]

  def validate_params(params) do
    with :ok <- validate(:from, params["from"]),
         :ok <- validate(:to, params["to"]),
         :ok <- validate(:limit, params["limit"]),
         :ok <- validate(:page, params["page"]),
         :ok <- from_less_than_to(params),
         do: :ok
  end

  defp validate(_key, value) when value in [nil, ""], do: :ok
  defp validate(:from, value), do: validate_datetime(:from, value)
  defp validate(:to, value), do: validate_datetime(:to, value)
  defp validate(key, value) do
    case Integer.parse(value) do
      {_number, ""} -> :ok
      _ -> invalid(key)
    end
  end

  defp validate_datetime(key, value) do
    case Integer.parse(value) do
      {_number, ""} -> :ok
      _ -> is_iso_datetime(key, value)
    end
  end

  defp from_less_than_to(params) do
    from = params["from"]
    to = params["to"]

    case {present?(from), present?(to), less_or_higher?(from, to)} do
      {true, true, true} -> {:invalid, "From can't be higher than to."}
      _ -> :ok
    end
  end

  defp present?(value) when value in [nil, ""], do: false
  defp present?(_value), do: true

  defp less_or_higher?(from, to) do
    from_date = convert_timestamp(from)
    to_date = convert_timestamp(to)
    case Calendar.DateTime.diff(to_date, from_date) do
      {:ok, _, _, :after} -> false
      {:ok, _, _, :before} -> true
    end
  end

  defp invalid(key), do: {:invalid, "The parameter '#{key}' isn't valid."}

  defp is_iso_datetime(key, datetime) do
    case Calendar.DateTime.Parse.rfc3339_utc(datetime) do
      {:ok, _} -> :ok
      {:bad_format, nil} -> invalid(key)
    end
  end

  defp convert_timestamp(timestamp) do
    case Calendar.DateTime.Parse.rfc3339_utc(timestamp) do
      {:ok, datetime} -> datetime
      {:bad_format, nil} ->
        timestamp
        |> to_integer
        |> Calendar.DateTime.Parse.unix!
    end
  end
end
