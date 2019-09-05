defmodule EvercamMedia.EvercamBot.Commands do
  use EvercamMedia.EvercamBot.Router
  use EvercamMedia.EvercamBot.Commander

  Application.ensure_all_started :inets

  @doc """
    Logger module injected from App.Commander
  """
  command ["start"] do
    Logger.log :info, "Command /start"
    send_message "Wellcome, write anything to show the main menu",
    reply_markup: %Model.ReplyKeyboardMarkup{
      keyboard: [
        [
          %{
            text: "Live view",
          },
        ],
        [
          %{
            text: "View all images",
          },
        ],
        [
          %{
            text: "Last comparison",
          },
        ],
        [
          %{
            text: "Last clip",
          },
        ]
      ]
    }
  end

  callback_query_command "choose" do
    Logger.log :info, "Callback Query Command /choose"
    id = String.downcase(update.callback_query.from.username)
    user = User.by_telegram_username(id)

    case update.callback_query.data do
      "/choose mycamera" ->
        "#{update.callback_query.message.text}"
        |> Camera.get_full
        |> get_photo(user, update)

      "/choose mycomparison" ->
        text = String.split("#{update.callback_query.message.text}", ".")
        id = Enum.at(text, 0)
        camera_exid = Enum.at(text, 1)
        compare = Compare.get_last_by_camera(id)

        case EvercamMedia.S3.do_load("#{camera_exid}/compares/#{compare.exid}/#{compare.exid}.mp4") do
          {:ok, response} -> send_file(response, update)
          {:error, response} -> send_message "#{camera_exid}: #{response.message}"
        end

      "/choose myclip" ->
        text = String.split("#{update.callback_query.message.text}", ".")
        id = Enum.at(text, 0)
        camera_exid = Enum.at(text, 1)
        archive = Archive.get_last_by_camera(id)

        case EvercamMedia.S3.do_load("#{camera_exid}/clips/#{archive.exid}/#{archive.exid}.mp4") do
          {:ok, response} -> send_file(response, update)
          {:error, response} -> send_message "#{camera_exid}: #{response.message}"
        end
      end
  end

  @doc """
    The `message` macro must come at the end since it matches anything.
    You may use it as a fallback.
  """
  message do
    id = update.message.chat.username
    user = User.by_telegram_username(id)
    cameras_list = Camera.for(user, true)
    case user do
      nil ->
        send_message "Unregistered user"
      _user ->
        case update.message.text do
          "Live view" ->
            Enum.each(cameras_list, fn(camera) ->
              {:ok, _} = send_message "#{camera.exid}",
                reply_markup: %Model.InlineKeyboardMarkup{
                  inline_keyboard: [
                    [
                      %{
                        callback_data: "/choose mycamera",
                        text: "\xF0\x9F\x93\xB9 #{camera.name}"
                      },
                    ],
                  ]
                }
              end)

          "View all images" ->
            Enum.each(cameras_list, fn(camera) -> get_photo(camera, user, update) end)

          "Last comparison" ->
            Enum.each(cameras_list, fn(camera) ->
              send_message "#{camera.id}.#{camera.exid}",
                reply_markup: %Model.InlineKeyboardMarkup{
                  inline_keyboard: [
                    [
                      %{
                        callback_data: "/choose mycomparison",
                        text: "\xF0\x9F\x93\xB9 #{camera.name}"
                      },
                    ],
                  ]
                }
              end)

            "Last clip" ->
              Enum.each(cameras_list, fn(camera) ->
                send_message "#{camera.id}.#{camera.exid}",
                  reply_markup: %Model.InlineKeyboardMarkup{
                    inline_keyboard: [
                      [
                        %{
                          callback_data: "/choose myclip",
                          text: "\xF0\x9F\x93\xB9 #{camera.name}"
                        },
                      ],
                    ]
                  }
                end)

              _ ->
                send_message "Command not found"
                Logger.log :info, "Command not found"
        end
    end
  end

  defp get_message(nil), do: "Camera not found"
  defp get_message(camera) do
    case camera.status do
      "online" -> "#{camera.name} is online but we can not get the live view, here is the last thumbnail:"
      "offline" -> "#{camera.name} is offline, here is the last thumbnail:"
      "project_finished" -> "Camera not found"
    end
  end

  defp get_photo(nil, _user, _update), do: Logger.log :info, "Camera not found"
  defp get_photo(_camera, nil, _update), do: Logger.log :info, "User not found"
  defp get_photo(camera, user, update) do
    case EvercamMediaWeb.SnapshotController.snapshot_with_user(camera, user, false) do
      {200, response} -> send_image(response[:image], update)
      {_, _} ->
        camera
        |> get_message
        |> send_message
        case EvercamMediaWeb.SnapshotController.snapshot_thumbnail(camera.exid, user, (if camera.status == "online", do: true, else: false)) do
          {200, img} -> send_image(img[:image], update)
          {404, img} -> send_image(img[:image], update)
          {403, img} -> send_message "#{img.message}"
        end
    end
  end

  defp send_image(image, update) do
    File.write!("image.png", image)
    send_photo("image.png")
    File.rm!("image.png")
  end

  defp send_file(video, update) do
    File.write("video.mp4", video)
    send_video("video.mp4")
    File.rm!("video.mp4")
  end
end
