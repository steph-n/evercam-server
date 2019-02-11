defmodule EvercamMediaWeb.CameraView do
  use EvercamMediaWeb, :view
  alias EvercamMedia.Util

  def render("index.v1.json", %{cameras: cameras, user: user}) do
    %{cameras: render_many(cameras, __MODULE__, "camera.v1.json", user: user)}
  end

  def render("index.v2.json", %{cameras: cameras, user: user}) do
    %{cameras: render_many(cameras, __MODULE__, "camera.v2.json", user: user)}
  end

  def render("show.v1.json", %{camera: camera, user: user}) do
    %{cameras: render_many([camera], __MODULE__, "camera.v1.json", user: user)}
  end

  def render("show.v2.json", %{camera: camera, user: user}) do
    %{cameras: render_many([camera], __MODULE__, "camera.v2.json", user: user)}
  end

  def render("camera.v1.json", %{camera: camera, user: user}) do
    if Permission.Camera.can_view?(user, camera) do
      base_camera_attributes(camera, user) |> Map.merge(privileged_camera_attributes(camera))
    else
      base_camera_attributes(camera, user)
    end
  end

  def render("camera.v2.json", %{camera: camera, user: user}) do
    if Permission.Camera.can_view?(user, camera) do
      base_camera_attributes_v2(camera, user) |> Map.merge(privileged_camera_attributes(camera))
    else
      base_camera_attributes_v2(camera, user)
    end
  end

  defp base_camera_attributes(camera, user) do
    %{
      id: camera.exid,
      name: camera.name,
      owned: Camera.is_owner?(user, camera),
      owner: camera.owner.username,
      vendor_id: Camera.get_vendor_attr(camera, :exid),
      vendor_name: Camera.get_vendor_attr(camera, :name),
      model_id: Camera.get_model_attr(camera, :exid),
      model_name: Camera.get_model_attr(camera, :name),
      created_at: Util.ecto_datetime_to_unix(camera.created_at),
      updated_at: Util.ecto_datetime_to_unix(camera.updated_at),
      last_polled_at: Util.ecto_datetime_to_unix(camera.last_polled_at),
      last_online_at: Util.ecto_datetime_to_unix(camera.last_online_at),
      is_online_email_owner_notification: is_send_notification?(camera.alert_emails, user),
      is_online: camera.is_online,
      is_public: camera.is_public,
      offline_reason: Util.get_offline_reason(camera.offline_reason),
      discoverable: camera.discoverable,
      timezone: Camera.get_timezone(camera),
      location: Camera.get_location(camera),
      rights: Camera.get_rights(camera, user),
      proxy_url: %{
        hls: Camera.get_hls_url(camera, User.get_fullname(user)),
        rtmp: Camera.get_rtmp_url(camera, User.get_fullname(user)),
      },
      thumbnail_url: thumbnail_url(camera),
    }
  end

  defp base_camera_attributes_v2(camera, user) do
    %{
      id: camera.exid,
      name: camera.name,
      owned: Camera.is_owner?(user, camera),
      owner: camera.owner.username,
      vendor_id: Camera.get_vendor_attr(camera, :exid),
      vendor_name: Camera.get_vendor_attr(camera, :name),
      model_id: Camera.get_model_attr(camera, :exid),
      model_name: Camera.get_model_attr(camera, :name),
      created_at: Util.datetime_to_iso8601(camera.created_at, Camera.get_timezone(camera)),
      updated_at: Util.datetime_to_iso8601(camera.updated_at, Camera.get_timezone(camera)),
      last_polled_at: Util.datetime_to_iso8601(camera.last_polled_at, Camera.get_timezone(camera)),
      last_online_at: Util.datetime_to_iso8601(camera.last_online_at, Camera.get_timezone(camera)),
      is_online_email_owner_notification: is_send_notification?(camera.alert_emails, user),
      is_online: camera.is_online,
      is_public: camera.is_public,
      offline_reason: Util.get_offline_reason(camera.offline_reason),
      discoverable: camera.discoverable,
      timezone: Camera.get_timezone(camera),
      location: Camera.get_location(camera),
      rights: Camera.get_rights(camera, user),
      proxy_url: %{
        hls: Camera.get_hls_url(camera, User.get_fullname(user)),
        rtmp: Camera.get_rtmp_url(camera, User.get_fullname(user)),
      },
      thumbnail_url: thumbnail_url(camera),
    }
  end

  defp privileged_camera_attributes(camera) do
    %{
      cam_username: Camera.username(camera),
      cam_password: Camera.password(camera),
      mac_address: Camera.get_mac_address(camera),
      external: %{
        host: Camera.host(camera, "external"),
        http: %{
          port: Camera.port(camera, "external", "http"),
          nvr_port: Camera.port(camera, "nvr", "http"),
          camera: Camera.external_url(camera, "http"),
          jpg: Camera.snapshot_url(camera, "jpg"),
          mjpg: Camera.snapshot_url(camera, "mjpg"),
        },
        rtsp: %{
          port: Camera.port(camera, "external", "rtsp"),
          mpeg: Camera.rtsp_url(camera, "external", "mpeg", false),
          audio: Camera.rtsp_url(camera, "external", "audio", false),
          h264: Camera.rtsp_url(camera, "external", "h264", false),
        },
      },
      internal: %{
        host: Camera.host(camera, "internal"),
        http: %{
          port: Camera.port(camera, "internal", "http"),
          camera: Camera.internal_url(camera, "http"),
          jpg: Camera.internal_snapshot_url(camera, "jpg"),
          mjpg: Camera.internal_snapshot_url(camera, "mjpg"),
        },
        rtsp: %{
          port: Camera.port(camera, "internal", "rtsp"),
          mpeg: Camera.rtsp_url(camera, "internal", "mpeg", false),
          audio: Camera.rtsp_url(camera, "internal", "audio", false),
          h264: Camera.rtsp_url(camera, "internal", "h264", false),
        },
      },
      cloud_recordings: cloud_recording(camera.cloud_recordings),
      timelapse_recordings: timelapse_recording(camera.timelapse_recordings)
    }
  end

  defp thumbnail_url(camera) do
    EvercamMediaWeb.Endpoint.static_url <> "/v1/cameras/" <> camera.exid <> "/thumbnail"
  end

  defp is_send_notification?(_emails, nil), do: false
  defp is_send_notification?(emails, _caller) when emails in [nil, ""], do: false
  defp is_send_notification?(emails, caller) do
    String.contains?(emails, caller.email)
  end

  defp cloud_recording(nil), do: nil
  defp cloud_recording(cloud_recording) do
    %{
      frequency: cloud_recording.frequency,
      storage_duration: cloud_recording.storage_duration,
      status: cloud_recording.status,
      schedule: cloud_recording.schedule
    }
  end

  defp timelapse_recording(nil), do: nil
  defp timelapse_recording(timelapse_recording) do
    %{
      frequency: timelapse_recording.frequency,
      storage_duration: timelapse_recording.storage_duration,
      status: timelapse_recording.status,
      schedule: timelapse_recording.schedule
    }
  end
end
