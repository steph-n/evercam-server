defmodule EvercamMedia.EvercamBot.Poller do
  use GenStage
  require Logger

  @doc """
    Server
  """

  def start_link() do
    Logger.log :info, "Started poller evercam_bot"
    GenStage.start_link __MODULE__, :ok, name: __MODULE__
  end

  def init(:ok) do
    update()
    {:producer, 0}
  end

  def handle_cast(:update, new_offset) do
    new_offset = Nadia.get_updates([offset: new_offset, timeout: 60])
                 |> process_messages

    {:noreply, [update()], new_offset + 1}
  end

  def handle_info(:timeout, offset) do
    update()
    {:noreply, offset}
  end

  @doc """
  Take care of unknown messages which otherwise would trigger function clause mismatch error.
  """
  def handle_info(_, state) do
    {:noreply, [], state}
  end

  @doc """
    Client
  """

  def update do
    GenStage.cast __MODULE__, :update
  end

  defp process_messages({:ok, []}), do: -1
  defp process_messages({:ok, results}) do
    results
    |> Enum.map(fn %{update_id: id} = message ->
      message
      |> process_message

      id
    end)
    |> List.last
  end
  defp process_messages({:error, %Nadia.Model.Error{reason: reason}}) do
    Logger.log :error, reason

    -1
  end
  defp process_messages({:error, error}) do
    Logger.log :error, error

    -1
  end
  defp process_message(nil), do: IO.puts "nil"
  defp process_message(message) do
    try do
      EvercamMedia.EvercamBot.Matcher.match message
    rescue
      err in MatchError ->
        Logger.log :warn, "Errored with #{err} at #{Poison.encode! message}"
    end
  end
end
