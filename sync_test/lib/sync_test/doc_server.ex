defmodule SyncTest.DocServer do
  use GenServer
  require Logger

  alias Y.Doc
  alias Y.Encoder

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get_full_state(server \\ __MODULE__) do
    GenServer.call(server, :get_full_state)
  end

  def apply_update(server \\ __MODULE__, update) do
    GenServer.call(server, {:apply_update, update})
  end

  def get_text(server \\ __MODULE__) do
    GenServer.call(server, :get_text)
  end

  # Callbacks

  @impl true
  def init(_opts) do
    # Create Y.Doc with client_id 0 for server
    {:ok, doc} = Doc.new(name: :sync_doc, client_id: 0)

    # Initialize with shared types for the demo:
    # - "prosemirror" XmlFragment (for y-prosemirror rich text editor)
    # - "items" Array (for list demo)
    # - "settings" Map (for key-value demo)
    Doc.transact(doc, fn transaction ->
      {:ok, _fragment, transaction} = Doc.get_xml_fragment(transaction, "prosemirror")
      {:ok, _array, transaction} = Doc.get_array(transaction, "items")
      {:ok, _map, transaction} = Doc.get_map(transaction, "settings")
      {:ok, transaction}
    end)

    Logger.info("DocServer started with Y.Doc :sync_doc (XmlFragment, Array, Map)")
    {:ok, %{doc_name: :sync_doc}}
  end

  @impl true
  def handle_call(:get_full_state, _from, state) do
    try do
      encoded = Encoder.encode(state.doc_name)
      {:reply, {:ok, encoded}, state}
    rescue
      e ->
        Logger.error("Error encoding doc: #{inspect(e)}")
        {:reply, {:error, e}, state}
    end
  end

  @impl true
  def handle_call({:apply_update, update}, _from, state) do
    result =
      Doc.transact(state.doc_name, fn transaction ->
        {:ok, Doc.apply_update(transaction, update)}
      end)

    case result do
      {:ok, _} ->
        # Log XmlFragment structure for debugging
        case Doc.get_xml_fragment(state.doc_name, "prosemirror") do
          {:ok, fragment} ->
            items = Y.Type.to_list(fragment, as_items: true, with_deleted: true)
            Logger.info("XmlFragment items after update: #{inspect(items, limit: :infinity, pretty: true)}")
          _ ->
            Logger.info("Could not get prosemirror fragment")
        end
        {:reply, {:ok, :applied}, state}

      error ->
        Logger.error("Failed to apply update: #{inspect(error)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_text, _from, state) do
    {:ok, text} = Doc.get_text(state.doc_name, "content")
    {:reply, {:ok, Y.Type.Text.to_string(text)}, state}
  end
end
