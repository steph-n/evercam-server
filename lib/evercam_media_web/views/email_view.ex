defmodule EvercamMediaWeb.EmailView do
  use EvercamMediaWeb, :view

  def full_name(user) do
    "#{user.firstname} #{user.lastname}"
  end

  def image_tag(has_thumbnail, snap_time \\ "") do
    case has_thumbnail do
      true -> "#{offline_message(snap_time)}<br><img src='cid:snapshot.jpg' alt='Camera Preview' style='width: 100%; display:block; margin:0 auto;'>"
      _ -> ""
    end
  end

  def get_shared_message(_, message) when message in [nil, ""], do: ""
  def get_shared_message(username, message) do
    width = (String.length(username)*7) + 138
    formatted_message =
      message
      |> String.split("\n", trim: true)
      |> Enum.reduce("", fn(msg, str_html) -> "#{str_html}<div style='margin-bottom: 12px;margin-left: 40px;'>#{msg}</div>" end)

    "<p style='line-height: 1.6; margin: 0 0 10px; padding: 0; clear'>
      <div style='width:#{width}px;height:20px;'>
        <div style='max-height:0;max-width:0;'>
          <div style='display: inline-block;background-color: rgb(255, 255, 255);font-weight: bold;top: 17px;width: #{width}px;height:20px;margin-top:10px;margin-left:5px;'>#{username}'s message for you:</div>
        </div>
      </div>

      <div style='border: solid 1px #e7e7e7;padding:5px;'>
        <br>
        #{formatted_message}
      </div>
    </p>
    <br>"
  end

  def snapmail_images(camera_images) do
    camera_images
    |> Enum.reduce("", fn(camera_image, mail_html) ->
      case !!camera_image.data do
        true ->
          "#{mail_html}<img class='last-snapmail-snapshot' id='#{camera_image.exid}' src='cid:#{camera_image.exid}.jpg' alt='Last Snapshot' style='width: 100%; display:block; margin:0 auto;'><br>
          <p style='line-height: 1.6; margin: 0 0 10px; padding: 0;'><b>#{camera_image.name}</b> (#{camera_image.exid}) - See the live view on Evercam by <a style='color:#428bca; text-decoration:none;' href='https://dash.evercam.io/v1/cameras/#{camera_image.exid}'>clicking here</a></p><br>"
        _ ->
          "#{mail_html}<p style='line-height: 1.6; margin: 0 0 10px; padding: 0;'><span id='#{camera_image.exid}' class='failed-camera'>Could not retrieve live image from</span> <a target='_blank' href='https://dash.evercam.io/v1/cameras/#{camera_image.exid}'>#{camera_image.name}</a></p>"
      end
    end)
  end

  def get_recordings_html(cloud_recordings, _) when cloud_recordings in [nil, ""], do: ""
  def get_recordings_html(cloud_recordings, label) do
    "<p style='line-height: 1.6; margin: 0 0 10px; padding: 0;'>
      #{label}:
      <table>
        <tbody>
          <tr>
            <th>Frequency</th>
            <td>#{cloud_recordings.frequency}</td>
          </tr>
          <tr>
            <th>Status</th>
            <td>#{cloud_recordings.status}</td>
          </tr>
          <tr>
            <th>Storage Duration</th>
            <td>#{cloud_recordings.storage_duration}</td>
          </tr>
          <tr>
            <th>Schedule</th>
            <td>#{Poison.encode!(cloud_recordings.schedule)}</td>
          </tr>
        </tbody>
      </table>
    </p>"
  end

  def get_dropbox_url(dropbox_url, snapshot_count) when snapshot_count > 0 do
    "<p style='line-height: 1.6; margin: 0 0 10px; padding: 0;'>
      You can see required files at <a style='color:#428bca; text-decoration:none;' href='#{dropbox_url}'>DropBox</a>
    </p>"
  end
  def get_dropbox_url(_, _), do: ""

  def get_user_name(email) do
    email
    |> User.by_username_or_email
    |> User.get_fullname
  end

  defp offline_message(str_time) when str_time in [nil, ""], do: ""
  defp offline_message(str_time) do
    "<br><p style='line-height: 1.6; margin: 0 0 10px; padding: 0;'>This is the last image we received from the camera on #{str_time}:</p>"
  end
end
