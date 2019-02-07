defmodule Snapmail do
  use EvercamMediaWeb, :model
  import Ecto.Changeset
  import Ecto.Query
  alias EvercamMedia.Repo

  @email_regex ~r/^(?!.*\.{2})[a-zA-Z0-9._%+"-]+@[a-zA-Z\d\-]+(\.[a-zA-Z]+)*\.[a-zA-Z]+\z/
  @required_fields [:subject, :notify_time]
  @optional_fields [:exid, :user_id, :recipients, :message, :notify_days, :timezone, :is_paused, :is_public]

  schema "snapmails" do
    belongs_to :user, User, foreign_key: :user_id
    has_many :snapmail_cameras, SnapmailCamera

    field :exid, :string
    field :subject, :string
    field :recipients, :string
    field :message, :string
    field :notify_days, :string
    field :notify_time, :string
    field :timezone, :string, default: "Etc/UTC"
    field :is_paused, :boolean, default: false
    field :is_public, :boolean, default: false
    timestamps(type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def all do
    Snapmail
    |> preload(:user)
    |> preload(:snapmail_cameras)
    |> preload([snapmail_cameras: :camera])
    |> preload([snapmail_cameras: [camera: :vendor_model]])
    |> preload([snapmail_cameras: [camera: [vendor_model: :vendor]]])
    |> Repo.all
  end

  def by_camera_id(id, user_id, conn) do
    Snapmail
    |> join(:inner, [snap], snap_cam in SnapmailCamera)
    |> where([snap, snap_cam], snap.id == snap_cam.snapmail_id)
    |> where([_, snap_cam], snap_cam.camera_id == ^id)
    |> where(user_id: ^user_id)
    |> preload(:user)
    |> preload(:snapmail_cameras)
    |> preload([snapmail_cameras: :camera])
    |> Repo.all(conn: conn)
  end

  def camera_and_user_id(camera_id, user_id) do
    Snapmail
    |> where(camera_id: ^camera_id)
    |> where(user_id: ^user_id)
    |> preload(:user)
    |> preload(:snapmail_cameras)
    |> preload([snapmail_cameras: :camera])
    |> Repo.all
  end

  def by_user_id(user_id) do
    Snapmail
    |> where(user_id: ^user_id)
    |> preload(:user)
    |> preload(:snapmail_cameras)
    |> preload([snapmail_cameras: :camera])
    |> Repo.all
  end

  def by_exid(exid) do
    Snapmail
    |> where(exid: ^String.downcase(exid))
    |> preload(:user)
    |> preload(:snapmail_cameras)
    |> preload([snapmail_cameras: :camera])
    |> Repo.one
  end

  def delete_no_camera_snapmail() do
    Snapmail
    |> join(:left, [snap], snap_cam in SnapmailCamera, on: snap_cam.snapmail_id == snap.id)
    |> where([snap, snap_cam], is_nil(snap_cam.id))
    |> Repo.all
    |> Enum.map(fn(snapmail) -> snapmail.id end)
    |> delete_multiple_by_id

  end

  def delete_multiple_by_id(ids) do
    Snapmail
    |> where([sm], sm.id in ^ids)
    |> Repo.delete_all
  end

  def delete_by_exid(exid) do
    Snapmail
    |> where(exid: ^exid)
    |> Repo.delete_all
  end

  def get_camera_ids(snapmail_cameras) do
    snapmail_cameras
    |> Enum.map(fn(snapmail_camera) -> snapmail_camera.camera end)
    |> Enum.map(fn(camera) -> camera.exid end)
    |> Enum.join(",")
  end

  def get_camera_names(snapmail_cameras) do
    snapmail_cameras
    |> Enum.map(fn(snapmail_camera) -> snapmail_camera.camera end)
    |> Enum.map(fn(camera) -> camera.name end)
    |> Enum.join(",")
  end

  def get_days_list(days) when days in [nil, ""], do: []
  def get_days_list(days) do
    days
    |> String.split(",", trim: true)
  end

  def get_timezone(snapmail) do
    case snapmail.timezone do
      nil -> "Etc/UTC"
      timezone -> timezone
    end
  end

  def scheduled_now?(days, timezone) do
    today =
      timezone
      |> Calendar.DateTime.now!
      |> Calendar.Date.day_of_week_name
    has_day =
      days
      |> Enum.filter(fn(day) -> day == today end)
      |> List.first
    case has_day do
      nil -> {:ok, false}
      "" -> {:ok, false}
      _day -> {:ok, true}
    end
  end

  def sleep(notify_time, nil) do
    sleep(notify_time, "UTC")
  end
  def sleep(notify_time, timezone) do
    [hours, minutes] = String.split notify_time, ":"
    {h, _} = Integer.parse(hours)
    {m, _} = Integer.parse(minutes)
    current_date =
      Calendar.DateTime.now_utc
      |> Calendar.DateTime.shift_zone!(timezone)

    %{year: year, month: month, day: day} = current_date
    {:ok, notify_date_time} =
      {{year, month, day}, {h, m, 59}}
      |> Calendar.DateTime.from_erl(timezone)
    case Calendar.DateTime.diff(notify_date_time, current_date) do
      {:ok, 0, _, :after} -> get_next_day_seconds(h, m, current_date, timezone)
      {:ok, seconds, _, :after} -> seconds * 1000
      _ -> get_next_day_seconds(h, m, current_date, timezone)
    end
  end

  defp get_next_day_seconds(hours, minutes, current_date, timezone) do
    seconds_of_next_day_alert = (60 * 60 * 24)
    %{year: year, month: month, day: day} = current_date
    notify_date_time =
      {{year, month, day}, {hours, minutes, 59}}
      |> Calendar.DateTime.from_erl(timezone)
      |> elem(1)
      |> Calendar.DateTime.advance!(seconds_of_next_day_alert)

    case Calendar.DateTime.diff(notify_date_time, current_date) do
      {:ok, seconds, _, :after} -> seconds * 1000
      _ -> raise "Seconds Calculate error"
    end
  end

  defp validate_exid(changeset) do
    case get_field(changeset, :exid) do
      nil -> auto_generate_camera_id(changeset)
      _exid -> changeset |> update_change(:exid, &String.downcase/1)
    end
  end

  defp auto_generate_camera_id(changeset) do
    case get_field(changeset, :subject) do
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

  def clean_recipients(recipients) do
    recipients
    |> String.split(",", trim: true)
    |> Enum.join(",")
  end

  defp validate_recipients(changeset) do
    case get_field(changeset, :recipients) do
      nil -> changeset
      recipients ->
        invalid_email =
          recipients
          |> String.split(",", trim: true)
          |> Enum.reject(fn(email) -> Regex.match? @email_regex, email end)
        case invalid_email do
          [] -> changeset |> update_change(:recipients, &clean_recipients/1)
          _ -> add_error(changeset, :recipients, "Invalid recipient email(s) #{invalid_email |> Enum.join(",")}.")
        end
    end
  end

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_exid
    |> validate_format(:notify_time, ~r/^\d{1,2}:\d{1,2}$/, message: "Notify time is invalid")
    |> validate_recipients
  end
end
