defmodule EvercamMedia.UserMailer do
  use Phoenix.Swoosh, view: EvercamMediaWeb.EmailView
  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.Snapshot.CamClient
  import SnapmailLogs, only: [save_snapmail: 4]

  @from Application.get_env(:evercam_media, EvercamMediaWeb.Endpoint)[:email]
  @no_reply "Evercam <no-reply@evercam.io>"
  @year Calendar.DateTime.now_utc |> Calendar.Strftime.strftime!("%Y")

  def cr_deletion_request(admin_name, admin_email, camera_exid, camera_name, start_date, end_date, image_count) do
    new()
    |> from(@from)
    |> to("marco@evercam.io")
    |> bcc("junaid@evercam.io")
    |> subject("Cloud Recordings has been deleted for \"#{camera_name}\"")
    |> render_body("cr_deletion.html", %{camera_name: camera_name, camera_exid: camera_exid, admin_email: admin_email, admin_name: admin_name, start_date: start_date, end_date: end_date, image_count: image_count, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def cr_settings_changed(current_user, camera, cloud_recording, old_cloud_recording, user_request_ip) do
    new()
    |> from(@from)
    |> to("marco@evercam.io")
    |> bcc("vinnie@evercam.io")
    |> subject("Cloud Recording has been updated for \"#{camera.name}\"")
    |> render_body("cr_settings_changed.html", %{camera: camera, current_user: current_user, cloud_recording: cloud_recording, old_cloud_recording: old_cloud_recording, user_request_ip: user_request_ip, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def send_snapmail_notification(email) do
    new()
    |> from(@from)
    |> to(email)
    |> subject("Snapmail - Sorry, here's the real message.")
    |> render_body("snapmail_notification.html", %{year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def confirm(user, code) do
    new()
    |> from(@no_reply)
    |> to(user.email)
    |> subject("Evercam Confirmation")
    |> render_body("confirm.html", %{user: user, code: code, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def camera_status(status, _user, camera) do
    timezone = camera |> Camera.get_timezone
    current_time = Calendar.DateTime.now_utc |> Calendar.DateTime.shift_zone!(timezone) |> Calendar.Strftime.strftime!("%A, %d %b %Y %H:%M")
    thumbnail = get_thumbnail(camera, status)
    camera.alert_emails
    |> String.split(",", trim: true)
    |> Enum.each(fn(email) ->
      new()
      |> from(@no_reply)
      |> to(email)
      |> add_attachment(thumbnail)
      |> subject("\"#{camera.name}\" camera is now #{status}")
      |> render_body("#{status}.html", %{user: email, camera: camera, thumbnail_available: !!thumbnail, year: @year, current_time: current_time})
      |> EvercamMedia.Mailer.deliver
    end)
  end

  def camera_offline_reminder(_user, camera, subject) do
    timezone = camera |> Camera.get_timezone
    current_time =
      camera.last_online_at
      |> Calendar.DateTime.shift_zone!(timezone)
      |> Calendar.Strftime.strftime!("%A, %d %b %Y %H:%M")
    thumbnail = get_thumbnail(camera)
    camera.alert_emails
    |> String.split(",", trim: true)
    |> Enum.each(fn(email) ->
      new()
      |> from(@no_reply)
      |> to(email)
      |> add_attachment(thumbnail)
      |> subject("#{subject} reminder: \"#{camera.name}\" camera has gone offline")
      |> render_body("offline.html", %{user: email, camera: camera, thumbnail_available: !!thumbnail, year: @year, current_time: current_time})
      |> EvercamMedia.Mailer.deliver
    end)
  end

  def camera_shared_notification(user, camera, sharee_email, message) do
    thumbnail = get_thumbnail(camera)
    new()
    |> from(@no_reply)
    |> to(sharee_email)
    |> bcc(user.email)
    |> add_attachment(thumbnail)
    |> reply_to(user.email)
    |> subject("#{User.get_fullname(user)} has shared the camera #{camera.name} with you.")
    |> render_body("camera_shared_notification.html", %{ user: user, camera: camera, message: message, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def camera_share_request_notification(user, camera, email, message, key) do
    thumbnail = get_thumbnail(camera)
    new()
    |> from(@no_reply)
    |> to(email)
    |> bcc(["#{user.email}", "marco@evercam.io", "vinnie@evercam.io", "erin@evercam.io", "azhar@evercam.io"])
    |> add_attachment(thumbnail)
    |> reply_to(user.email)
    |> subject("#{User.get_fullname(user)} has shared the camera #{camera.name} with you.")
    |> render_body("sign_up_to_share_email.html", %{user: user, camera: camera, message: message, key: key, sharee: email, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def accepted_share_request_notification(user, camera, email) do
    thumbnail = get_thumbnail(camera)
    new()
    |> from(@no_reply)
    |> to(user.email)
    |> add_attachment(thumbnail)
    |> subject("#{email} has accepted your request to view your camera")
    |> render_body("accepted_share_request.html", %{user: user, camera: camera, sharee: email, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def revoked_share_request_notification(user, camera, email) do
    thumbnail = get_thumbnail(camera)
    new()
    |> from(@no_reply)
    |> to(user.email)
    |> bcc(["marco@evercam.io", "vinnie@evercam.io", "erin@evercam.io"])
    |> add_attachment(thumbnail)
    |> subject("#{email} did not accept your request to view your camera")
    |> render_body("revoke_share_request.html", %{user: user, camera: camera, sharee: email, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def camera_create_notification(user, camera) do
    thumbnail = get_thumbnail(camera)
    new()
    |> from(@no_reply)
    |> to(user.email)
    |> bcc(["marco@evercam.io", "vinnie@evercam.io", "erin@evercam.io"])
    |> add_attachment(thumbnail)
    |> subject("A new camera has been added to your account")
    |> render_body("camera_create_notification.html", %{user: user, camera: camera, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def password_reset_request(user) do
    new()
    |> from(@no_reply)
    |> to(user.email)
    |> subject("Password reset requested for Evercam")
    |> render_body("password_reset_request.html", %{user: user, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def archive_completed(archive, email) do
    thumbnail = Storage.load_archive_thumbnail(archive.camera.exid, archive.exid)
    new()
    |> from(@no_reply)
    |> to(email)
    |> add_attachment(thumbnail)
    |> subject("Archive #{archive.title} is ready.")
    |> render_body("archive_create_completed.html", %{archive: archive, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def archive_failed(archive, email) do
    thumbnail = get_thumbnail(archive.camera)
    archive_failed_dev(archive, thumbnail)
    new()
    |> from(@no_reply)
    |> to(email)
    |> add_attachment(thumbnail)
    |> subject("Archive #{archive.title} is failed.")
    |> render_body("archive_create_failed.html", %{archive: archive, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def archive_failed_dev(archive, thumbnail) do
    new()
    |> from(@from)
    |> to("azhar@evercam.io")
    |> bcc("marco@evercam.io")
    |> add_attachment(thumbnail)
    |> subject("Archive #{archive.title} is failed.")
    |> render_body("archive_create_failed_dev.html", %{archive: archive, thumbnail_available: !!thumbnail, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def snapmail(id, notify_time, recipients, camera_images, timestamp) do
    attachments = get_multi_attachments(camera_images)
    recipients
    |> String.split(",", trim: true)
    |> Enum.each(fn(recipient) ->
      new()
      |> from({"Evercam Snapmail", "snapmail@evercam.io"})
      |> to(recipient)
      |> add_multi_attachment(attachments)
      |> subject("Your Scheduled SnapMail @ #{notify_time}")
      |> render_body("snapmail.html", %{id: id, recipient: recipient, notify_time: notify_time, camera_images: camera_images, year: @year})
      |> EvercamMedia.Mailer.deliver
    end)
    save_snapmail(recipients, "Your Scheduled SnapMail @ #{notify_time}",
      Phoenix.View.render_to_string(EvercamMediaWeb.EmailView, "snapmail.html", id: id, recipient: "history_user", notify_time: notify_time, camera_images: camera_images, year: @year), "#{timestamp}")
  end

  def snapshot_extraction_started(snapshot_extractor, type) do
    from_d = get_formatted_date(snapshot_extractor.from_date)
    to_d = get_formatted_date(snapshot_extractor.to_date)
    new()
    |> from(@no_reply)
    |> to(snapshot_extractor.requestor)
    |> bcc(["marco@evercam.io", "junaid@evercam.io"])
    |> subject("Snapshot Extraction (#{type}) started")
    |> render_body("snapshot_extractor_alert.html", %{snapshot_extractor: snapshot_extractor, from_d: from_d, to_d: to_d, interval: humanize_interval(snapshot_extractor.interval), year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def snapshot_extraction_completed(snapshot_extractor, count, expected_count, execution_time) do
    url = get_dropbox_url(snapshot_extractor)
    new()
    |> from(@no_reply)
    |> to(snapshot_extractor.requestor)
    |> bcc(["marco@evercam.io", "junaid@evercam.io"])
    |> subject("Snapshot Extraction (Cloud) Completed")
    |> render_body("snapshot_extractor_complete.html", %{camera: snapshot_extractor.camera.name, count: count, expected_count: expected_count, dropbox_url: url, execution_time: execution_time, year: @year, type: "cloud"})
    |> EvercamMedia.Mailer.deliver
  end
  def snapshot_extraction_completed(snapshot_extractor, snap_count) do
    url = get_dropbox_url(snapshot_extractor)
    new()
    |> from(@no_reply)
    |> to(snapshot_extractor.requestor)
    |> subject("Snapshot Extraction (Local) Completed")
    |> render_body("snapshot_extractor_complete.html", %{camera: snapshot_extractor.camera.name, count: snap_count, expected_count: nil, execution_time: nil, dropbox_url: url, year: @year, type: "local"})
    |> EvercamMedia.Mailer.deliver
  end

  def timelapse_creator_started(e_start_date, e_to_date, e_schedule, e_interval, camera_name, requestor, duration) do
    new()
    |> from(@no_reply)
    |> to("#{requestor}")
    |> bcc(["marco@evercam.io","javier@evercam.io"])
    |> subject("Time-lapse Creator Started")
    |> render_body("timelapse_started.html", %{start_date: e_start_date, to_date: e_to_date, interval: e_interval, schedule: e_schedule, camera_name: camera_name, requestor: requestor, duration: duration, year: @year})
    |> EvercamMedia.Mailer.deliver
  end

  def timelapse_creator_completed(count, camera_name, expected_count, extractor_id, camera_exid, requestor, execution_time, duration) do
    new()
    |> from(@no_reply)
    |> to("#{requestor}")
    |> bcc(["marco@evercam.io","javier@evercam.io"])
    |> subject("Time-lapse Completed")
    |> render_body("timelapse_completed.html", %{count: count, camera_name: camera_name, expected_count: expected_count, extractor_id: extractor_id, camera_exid: camera_exid, execution_time: execution_time, requestor: requestor, year: @year, duration: duration})
    |> EvercamMedia.Mailer.deliver
  end

  defp get_thumbnail(camera, status \\ "")
  defp get_thumbnail(camera, "online") do
    case camera |> construct_args |> fetch_snapshot do
      {:ok, data} -> data
      {:error, _error} -> try_get_thumbnail(camera, 3)
    end
  end
  defp get_thumbnail(camera, _status) do
    try_get_thumbnail(camera, 1)
  end

  defp try_get_thumbnail(camera, 3) do
    case Storage.thumbnail_load(camera.exid) do
      {:ok, _, ""} -> nil
      {:ok, _, image} -> image
      _ -> nil
    end
  end
  defp try_get_thumbnail(camera, attempt) do
    case Storage.thumbnail_load(camera.exid) do
      {:ok, _, ""} -> try_get_thumbnail(camera, attempt + 1)
      {:ok, _, image} -> image
      _ -> nil
    end
  end

  defp add_attachment(email, nil), do: email
  defp add_attachment(email, thumbnail) do
    email |> attachment(Swoosh.Attachment.new({:data, thumbnail}, filename: "snapshot.jpg", content_type: "image/jpeg", type: :inline))
  end

  defp add_multi_attachment(email, []), do: email
  defp add_multi_attachment(email, content_filename) do
    Enum.reduce(content_filename, email, fn c_f, email_with_attachment = _acc ->
      email_with_attachment
      |> attachment(Swoosh.Attachment.new({:data, c_f.content}, filename: "#{c_f.filename}", content_type: "image/jpeg", type: :inline))
      |> attachment(Swoosh.Attachment.new({:data, c_f.content}, filename: "#{c_f.filename}", content_type: "image/jpeg"))
    end)
  end

  defp get_multi_attachments(camera_images) do
    camera_images
    |> Enum.map(fn(camera_image) ->
      if !!camera_image.data do
        %{content: camera_image.data, filename: "#{camera_image.exid}.jpg"}
      end
    end)
    |> Enum.reject(fn(content) -> content == nil end)
  end

  defp fetch_snapshot(args, attempt \\ 1) do
    response = CamClient.fetch_snapshot(args)

    case {response, attempt} do
      {{:error, _error}, attempt} when attempt <= 3 ->
        fetch_snapshot(args, attempt + 1)
      _ -> response
    end
  end

  defp construct_args(camera) do
    %{
      camera_exid: camera.exid,
      status: camera.status,
      url: Camera.snapshot_url(camera),
      username: Camera.username(camera),
      password: Camera.password(camera),
      vendor_exid: Camera.get_vendor_attr(camera, :exid),
      auth: Camera.get_auth_type(camera)
    }
  end

  defp humanize_interval(5),     do: "1 Frame Every 5 sec"
  defp humanize_interval(10),    do: "1 Frame Every 10 sec"
  defp humanize_interval(15),    do: "1 Frame Every 15 sec"
  defp humanize_interval(20),    do: "1 Frame Every 20 sec"
  defp humanize_interval(30),    do: "1 Frame Every 30 sec"
  defp humanize_interval(60),    do: "1 Frame Every 1 min"
  defp humanize_interval(300),   do: "1 Frame Every 5 min"
  defp humanize_interval(600),   do: "1 Frame Every 10 min"
  defp humanize_interval(900),   do: "1 Frame Every 15 min"
  defp humanize_interval(1200),  do: "1 Frame Every 20 min"
  defp humanize_interval(1800),  do: "1 Frame Every 30 min"
  defp humanize_interval(3600),  do: "1 Frame Every hour"
  defp humanize_interval(7200),  do: "1 Frame Every 2 hour"
  defp humanize_interval(21600), do: "1 Frame Every 6 hour"
  defp humanize_interval(43200), do: "1 Frame Every 12 hour"
  defp humanize_interval(86400), do: "1 Frame Every 24 hour"
  defp humanize_interval(1),     do: "All"
  defp humanize_interval(0),     do: "All"

  defp get_formatted_date(datetime) do
    datetime |> Calendar.Strftime.strftime!("%A, %d %b %Y %H:%M")
  end

  defp get_dropbox_url(snapshot_extractor) do
    "https://www.dropbox.com/home/#{construction_request(snapshot_extractor.requestor)}/#{snapshot_extractor.camera.exid}/#{snapshot_extractor.id}"
  end

  defp construction_request("marklensmen@gmail.com"), do: "Construction"
  defp construction_request(_), do: "Construction2"
end
