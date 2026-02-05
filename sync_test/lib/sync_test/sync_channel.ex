defmodule SyncTest.SyncChannel do
  use Phoenix.Channel
  require Logger

  alias SyncTest.DocServer

  def join("sync:lobby", _params, socket) do
    Logger.info("Client joining sync:lobby")
    send(self(), :after_join)
    {:ok, socket}
  end

  # Send full state on join
  def handle_info(:after_join, socket) do
    case DocServer.get_full_state() do
      {:ok, state} ->
        Logger.info("Sending initial state to client (#{byte_size(state)} bytes)")
        push(socket, "sync_state", %{data: Base.encode64(state)})

      {:error, reason} ->
        Logger.error("Failed to get doc state: #{inspect(reason)}")
    end

    {:noreply, socket}
  end

  # Receive update from client
  def handle_in("update", %{"data" => data}, socket) do
    case Base.decode64(data) do
      {:ok, update} ->
        Logger.info("Received update from client (#{byte_size(update)} bytes)")
        # Log the raw bytes for debugging
        Logger.debug("Update bytes: #{inspect(update, limit: :infinity)}")

        case DocServer.apply_update(update) do
          {:ok, _} ->
            # Broadcast to all OTHER clients
            Logger.info("Broadcasting update to other clients")
            broadcast_from!(socket, "update", %{data: data})
            {:reply, :ok, socket}

          {:error, reason} ->
            Logger.error("Failed to apply update: #{inspect(reason)}")
            {:reply, {:error, %{reason: inspect(reason)}}, socket}
        end

      :error ->
        Logger.error("Failed to decode base64 update")
        {:reply, {:error, %{reason: "invalid base64"}}, socket}
    end
  end

  # Client requests full sync
  def handle_in("sync_request", _params, socket) do
    case DocServer.get_full_state() do
      {:ok, state} ->
        {:reply, {:ok, %{data: Base.encode64(state)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end
end
