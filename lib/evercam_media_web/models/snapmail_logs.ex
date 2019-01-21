defmodule SnapmailLogs do
  use EvercamMediaWeb, :model
  alias EvercamMedia.SnapshotRepo
  alias EvercamMedia.Util
  require Logger

  @required_fields [:body]
  @optional_fields [:subject, :recipients, :image_timestamp]

  schema "snapmail_logs" do
    field :recipients, :string
    field :subject, :string
    field :body, :string
    field :image_timestamp, :string

    timestamps(type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def save_snapmail(recipients, subject, body, image_timestamp) do
    SnapmailLogs.changeset(%SnapmailLogs{}, %{
      recipients: recipients,
      subject: subject,
      body: body,
      image_timestamp: image_timestamp
    })
    |> SnapshotRepo.insert
    |> handle_save_results
  end

  defp handle_save_results({:ok, _}), do: :noop
  defp handle_save_results({:error, changeset}), do: Logger.info Util.parse_changeset(changeset)

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
