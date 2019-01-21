defmodule Timelapse do
  use EvercamMediaWeb, :model
  import Ecto.Changeset
  import Ecto.Query
  alias EvercamMedia.Repo

  @required_fields [:camera_id, :user_id, :title, :frequency, :status, :date_always, :time_always]
  @optional_fields [:exid, :snapshot_count, :resolution, :from_datetime, :to_datetime, :watermark_logo, :watermark_position, :recreate_hls, :start_recreate_hls, :last_snapshot_at, :extra]

  # @status %{active: 0, scheduled: 1, expired: 2, paused: 3, stopped: 4}

  schema "timelapses" do
    belongs_to :user, User, foreign_key: :user_id
    belongs_to :camera, Camera, foreign_key: :camera_id

    field :exid, :string
    field :title, :string
    field :frequency, :integer
    field :snapshot_count, :integer
    field :resolution, :string
    field :status, :integer, default: 0

    field :date_always, :boolean
    field :from_datetime, :utc_datetime_usec, default: Calendar.DateTime.now_utc
    field :time_always, :boolean
    field :to_datetime, :utc_datetime_usec, default: Calendar.DateTime.now_utc
    field :watermark_logo, :string
    field :watermark_position, :string
    field :recreate_hls, :boolean, default: false
    field :start_recreate_hls, :boolean, default: false
    field :hls_created, :boolean, default: false
    field :last_snapshot_at, :utc_datetime_usec
    field :extra, EvercamMedia.Types.JSON

    timestamps(type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def all do
    Timelapse
    |> preload(:camera)
    |> preload([camera: :owner])
    |> preload([camera: :vendor_model])
    |> preload([camera: [vendor_model: :vendor]])
    |> Repo.all
  end

  def by_camera_id(id) do
    Timelapse
    |> where(camera_id: ^id)
    |> preload(:camera)
    |> preload([camera: :owner])
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all
  end

  def by_user_id(user_id) do
    Timelapse
    |> where(user_id: ^user_id)
    |> preload(:camera)
    |> preload([camera: :owner])
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all
  end

  def by_exid(exid) do
    Timelapse
    |> where(exid: ^String.downcase(exid))
    |> preload(:camera)
    |> preload([camera: :owner])
    |> Repo.one
  end

  def delete_by_exid(exid) do
    Timelapse
    |> where(exid: ^exid)
    |> Repo.delete_all
  end

  def delete_by_id(id) do
    Timelapse
    |> where(id: ^id)
    |> Repo.delete_all
  end

  def delete_by_camera_id(camera_id) do
    Timelapse
    |> where(camera_id: ^camera_id)
    |> Repo.delete_all
  end

  def scheduled_now?(timezone, from_date, to_date, date_always, time_always) do
    current_time = Calendar.DateTime.now!(timezone)
    from_date = Calendar.DateTime.shift_zone!(from_date, timezone)
    to_date = Calendar.DateTime.shift_zone!(to_date, timezone)

    is_scheduled_now?(timezone, current_time, from_date, to_date, date_always, time_always)
  end

  def is_scheduled_now?(_timezone, _current_time, _from_date, _to_date, true, true), do: {:ok, true}
  def is_scheduled_now?(_timezone, current_time, from_date, to_date, false, false) do
    between?(current_time, from_date, to_date)
  end
  def is_scheduled_now?(timezone, current_time, from_date, to_date, true, false) do
    %{year: current_year, month: current_month, day: current_day} = current_time
    %{hour: from_hour, minute: from_minute} = from_date
    %{hour: to_hour, minute: to_minute} = to_date
    start_date = {{current_year, current_month, current_day}, {from_hour, from_minute, 0}} |> Calendar.DateTime.from_erl!(timezone)

    case Calendar.DateTime.diff(from_date, to_date) do
      {:ok, _seconds, _, :after} ->
        %{year: next_year, month: next_month, day: next_day} = current_time |> Calendar.DateTime.advance!(60 * 60 * 24)
        end_date = {{next_year, next_month, next_day}, {to_hour, to_minute, 59}} |> Calendar.DateTime.from_erl!(timezone)
        between?(current_time, start_date, end_date)
      _ ->
        end_date = {{current_year, current_month, current_day}, {to_hour, to_minute, 59}} |> Calendar.DateTime.from_erl!(timezone)
        between?(current_time, start_date, end_date)
    end
  end
  def is_scheduled_now?(timezone, current_time, from_date, to_date, false, true) do
    %{year: from_year, month: from_month, day: from_day} = from_date
    %{year: to_year, month: to_month, day: to_day} = to_date
    start_date = {{from_year, from_month, from_day}, {0, 0, 0}} |> Calendar.DateTime.from_erl!(timezone)
    end_date = {{to_year, to_month, to_day}, {23, 59, 59}} |> Calendar.DateTime.from_erl!(timezone)

    between?(current_time, start_date, end_date)
  end

  defp between?(current_time, from_date, to_date) do
    check = current_time |> Calendar.DateTime.Format.unix
    start = from_date |> Calendar.DateTime.Format.unix
    the_end = to_date |> Calendar.DateTime.Format.unix
    case check >= start && check < the_end do
      true ->
        {:ok, true}
      _ ->
        {:ok, false}
    end
  end

  def create_timelapse(timelapse_params) do
    timelapse_changeset = create_changeset(%Timelapse{}, timelapse_params)

    case Repo.insert(timelapse_changeset) do
      {:ok, timelapse} ->
        camera_timelapse =
          timelapse
          |> Repo.preload(:camera)
          |> Repo.preload([camera: :owner])
          |> Repo.preload([camera: :vendor_model])
          |> Repo.preload([camera: [vendor_model: :vendor]])
        {:ok, camera_timelapse}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_timelapse(timelapse, params) do
    timelapse_changeset = changeset(timelapse, params)
    case Repo.update(timelapse_changeset) do
      {:ok, timelapse} ->
        camera_timelapse =
          timelapse
          |> Repo.preload(:camera)
          |> Repo.preload([camera: :owner])
          |> Repo.preload([camera: :vendor_model])
          |> Repo.preload([camera: [vendor_model: :vendor]])
        {:ok, camera_timelapse}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp validate_exid(changeset) do
    case get_field(changeset, :exid) do
      nil -> auto_generate_camera_id(changeset)
      _exid -> changeset |> update_change(:exid, &String.downcase/1)
    end
  end

  defp auto_generate_camera_id(changeset) do
    case get_field(changeset, :title) do
      nil ->
        changeset
      subject ->
        camera_id =
          subject
          |> EvercamMedia.Util.slugify
          |> String.replace(" ", "")
          |> String.replace("-", "")
          |> String.downcase
          |> String.slice(0..4)
        put_change(changeset, :exid, "#{camera_id}-#{Enum.take_random(?a..?z, 5)}")
    end
  end

  defp validate_from_to_datetime(changeset) do
    date_always = get_field(changeset, :date_always)
    time_always = get_field(changeset, :time_always)
    from_datetime = get_field(changeset, :from_datetime)
    to_datetime = get_field(changeset, :to_datetime)
    case validate_datetime_parameter(from_datetime, to_datetime, date_always, time_always) do
      {:ok} -> changeset
      {:invalid, message} -> add_error(changeset, :invalid_from_to_datetime, message)
    end
  end

  defp validate_datetime_parameter(_from, _to, true, true), do: {:ok}
  defp validate_datetime_parameter(from, to, date_always, time_alwasy) do
    cond do
      !date_always && is_nil(from) || is_nil(to) ->
        {:invalid, "From and To date can't be blank."}
      !time_alwasy && is_nil(from) || is_nil(to) ->
        {:invalid, "From and To time can't be blank."}
      is_valid_datetime?(from, to) ->
        {:invalid, "From date cannot be greater than current time."}
      is_valid_datetime?(Calendar.DateTime.now!("UTC"), to) ->
        {:invalid, "To date cannot be less than current time."}
      true -> {:ok}
    end
  end

  def is_valid_datetime?(from, to) do
    case Calendar.DateTime.diff(from, to) do
      {:ok, _, _, :after} -> true
      _ -> false
    end
  end

  def create_changeset(model, params \\ :invalid) do
    model
    |> changeset(params)
    |> validate_from_to_datetime
  end

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_exid
  end
end
