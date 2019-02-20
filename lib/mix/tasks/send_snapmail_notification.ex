defmodule EvercamMedia.SendSnapmailNotification do
  alias Evercam.Repo
  alias EvercamMedia.UserMailer
  import Ecto.Query

  def send do
    from(s in Snapmail, select: %{emails: s.recipients})
    |> Repo.all
    |> Enum.reduce([], fn email, map = _acc ->
      %{emails: emails} = email
      Enum.concat(map, emails |> into_list)
    end) |> send_multiple_emails()
  end

  defp into_list(nil), do: []
  defp into_list(emails), do: emails |> String.split(",")

  defp send_multiple_emails(emails) do
    send_email = fn email ->
      UserMailer.send_snapmail_notification(email)
    end
    emails
    |> Task.async_stream(send_email, max_concurrency: 10, timeout: :infinity)
    |> Stream.run
  end
end
