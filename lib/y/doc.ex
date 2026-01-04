defmodule Y.Doc do
  alias __MODULE__
  alias Y.Type
  alias Y.ID
  alias Y.Item
  alias Y.Type.Array
  alias Y.Type.Unknown
  alias Y.Transaction
  alias Y.Decoder

  require Logger

  @type t :: %__MODULE__{
          gc: term(),
          gc_filter: (-> boolean()) | nil,
          client_id: integer(),
          collection_id: term(),
          share: Map.t(),
          transaction: term(),
          subdocs: MapSet.t(),
          item: term(),
          should_load: boolean(),
          autoload: boolean(),
          meta: term(),
          loaded?: boolean(),
          synced?: boolean(),
          delete_set: Map.t(),
          pending_structs: Map.t() | nil,
          pending_delete_sets: Map.t() | nil
        }

  defstruct name: nil,
            gc: nil,
            gc_filter: nil,
            client_id: nil,
            collection_id: nil,
            share: %{},
            transaction: nil,
            subdocs: MapSet.new(),
            item: nil,
            should_load: true,
            autoload: false,
            meta: nil,
            loaded?: false,
            synced?: false,
            delete_set: %{},
            pending_structs: nil,
            pending_delete_sets: nil

  def start_link(opts \\ []) do
    opts = compose_opts(opts)

    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  def start(opts \\ []) do
    opts = compose_opts(opts)

    GenServer.start(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  def init(opts) do
    doc = %Doc{
      name: opts[:name],
      collection_id: opts[:collection_id],
      gc: opts[:gc],
      gc_filter: opts[:gc_filter],
      meta: opts[:meta],
      autoload: opts[:autoload],
      should_load: opts[:should_load],
      client_id: opts[:client_id]
    }

    {:ok, doc}
  end

  def new(opts \\ []) do
    with {:ok, pid} <- start_link(opts),
         {:ok, %Doc{name: name}} <- get_instance(pid) do
      {:ok, name}
    end
  end

  def get_array(doc_name_or_transaction, array_name \\ UUID.uuid4())

  def get_array(%Transaction{doc: doc} = transaction, array_name) do
    case do_get_array(doc, array_name) do
      {:ok, array, doc} -> {:ok, array, %{transaction | doc: doc}}
      {:error, _} = err -> err
    end
  end

  def get_array(doc_name, array_name) do
    GenServer.call(doc_name, {:get_array, array_name})
  end

  def get_map(transaction, map_name \\ UUID.uuid4())

  def get_map(%Transaction{doc: doc} = transaction, map_name) do
    case do_get_map(doc, map_name) do
      {:ok, map, doc} -> {:ok, map, %{transaction | doc: doc}}
      {:error, _} = err -> err
    end
  end

  def get_map(doc_name, map_name) do
    GenServer.call(doc_name, {:get_map, map_name})
  end

  def get_text(transaction, text_name \\ UUID.uuid4())

  def get_text(%Transaction{doc: doc} = transaction, text_name) do
    case do_get_text(doc, text_name) do
      {:ok, text, doc} -> {:ok, text, %{transaction | doc: doc}}
      {:error, _} = err -> err
    end
  end

  def get_text(doc_name, text_name) do
    GenServer.call(doc_name, {:get_text, text_name})
  end

  def transact(doc_name, f, opts \\ []) do
    GenServer.call(doc_name, {:transact, f, opts})
  end

  def transact!(doc_name, f, opts \\ []) do
    case GenServer.call(doc_name, {:transact, f, opts}) do
      {:ok, doc} -> doc
      _ -> raise "Failed to run transact"
    end
  end

  def get(%Transaction{doc: doc}, name), do: get!(doc, name)

  def get(doc_name, name) do
    with {:ok, doc} <- get_instance(doc_name) do
      get!(doc, name)
    end
  end

  def get!(%Doc{share: share}, name) when is_map_key(share, name),
    do: Map.fetch(share, name)

  def get!(%Doc{}, name), do: {:error, "Type #{name} does not exist"}

  def get_or_create_unknown(%Transaction{doc: %Doc{} = doc} = transaction, name) do
    case get(transaction, name) do
      {:ok, type} ->
        {:ok, type, transaction}

      {:error, _} ->
        type = Unknown.new(doc, name)
        {:ok, type, %{transaction | doc: %{doc | share: Map.put_new(doc.share, name, type)}}}
    end
  end

  def highest_clock(%Transaction{doc: doc}, client_id \\ nil) do
    highest_clock!(doc, client_id)
  end

  def highest_clock!(%Doc{} = doc, client_id \\ nil) do
    Enum.reduce(Map.values(doc.share), 0, fn t, acc ->
      max(acc, Type.highest_clock(t, client_id))
    end)
  end

  def highest_clock_by_client_id(%Transaction{doc: doc}), do: highest_clock_by_client_id!(doc)

  def highest_clock_by_client_id!(%Doc{} = doc) do
    Enum.reduce(Map.values(doc.share), %{}, fn t, acc ->
      Map.merge(acc, Type.highest_clock_by_client_id(t), fn _k, v1, v2 ->
        max(v1, v2)
      end)
    end)
  end

  def highest_clock_with_length(%Transaction{doc: doc}, client_id \\ nil) do
    highest_clock_with_length!(doc, client_id)
  end

  @doc """
  Make sure that %Doc{} = doc is not stale. 
  Better to use highest_clock_with_length within transaction
  """
  def highest_clock_with_length!(%Doc{} = doc, client_id) do
    Enum.reduce(Map.values(doc.share), 0, fn t, acc ->
      max(acc, Type.highest_clock_with_length(t, client_id))
    end)
  end

  def highest_clock_with_length_by_client_id(%Transaction{doc: doc}),
    do: highest_clock_with_length_by_client_id!(doc)

  def highest_clock_with_length_by_client_id!(%Doc{} = doc) do
    Enum.reduce(Map.values(doc.share), %{}, fn t, acc ->
      Map.merge(acc, Type.highest_clock_with_length_by_client_id(t), fn _k, v1, v2 ->
        max(v1, v2)
      end)
    end)
  end

  def find_item(transaction, type_name \\ nil, id, default \\ nil)

  def find_item(%Transaction{doc: doc}, nil, %ID{} = id, default) do
    find_item!(doc, id, default)
  end

  def find_item(%Transaction{} = transaction, type_name, %ID{} = id, default) do
    with {:ok, parent} <- get(transaction, type_name) do
      Type.find(parent, id, default)
    else
      _ -> nil
    end
  end

  def find_item!(%Doc{} = doc, %ID{} = id, default \\ nil) do
    doc.share
    |> Map.values()
    |> Enum.find_value(fn t -> Type.find(t, id, default) end)
  end

  def find_parent_item!(%Doc{} = doc, %Item{} = child_item) do
    doc.share
    |> Map.values()
    |> Enum.find_value(fn type ->
      do_find_parent(type, child_item)
    end)
  end

  def find_parent_item!(doc_name, %Item{} = child_item) do
    with {:ok, doc} <- get_instance(doc_name) do
      find_parent_item!(doc, child_item)
    end
  end

  def items_of_client!(%Doc{} = doc, client) do
    doc.share
    |> Map.values()
    |> Enum.flat_map(fn type ->
      type
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.filter(fn %_{id: %ID{client: c}} -> c == client end)
    end)
    |> Enum.sort_by(fn %_{id: %ID{clock: clock}} -> clock end)
  end

  def type_with_id!(%Doc{} = doc, %ID{} = id) do
    doc.share
    |> Map.values()
    |> Enum.filter(fn type -> Type.highest_clock_with_length(type) >= id.clock end)
    |> Enum.find(fn type ->
      type
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.find(fn %{id: item_id} -> item_id == id end)
    end)
  end

  def replace(%Doc{} = doc, %{name: name} = type) do
    share =
      doc.share
      |> Enum.map(fn {d_name, d_type} ->
        case d_name do
          ^name -> {name, type}
          _ -> {d_name, replace_recursively(d_type, type)}
        end
      end)
      |> Enum.into(%{})

    %{doc | share: share}
  end

  def pack(%Transaction{doc: %Doc{} = doc} = transaction) do
    %{transaction | doc: pack!(doc)}
  end

  def pack!(%Doc{share: share, delete_set: delete_set} = doc) do
    share =
      share
      |> Enum.map(fn {name, type} ->
        {name, Type.pack(type)}
      end)
      |> Enum.into(%{})

    delete_set =
      delete_set
      |> Enum.map(fn {client, set} ->
        new_set =
          set
          |> Enum.sort_by(fn {clock, _length} -> clock end)
          |> Enum.reduce([], fn
            kv, [] ->
              [kv]

            {clock, length}, [{last_clock, last_length} | rest] = acc ->
              if last_clock + last_length == clock do
                [{last_clock, last_length + length} | rest]
              else
                [{clock, length} | acc]
              end
          end)
          |> MapSet.new()

        {client, new_set}
      end)
      |> Enum.into(%{})

    %{doc | share: share, delete_set: delete_set}
  end

  def apply_update(transaction, update) when is_bitstring(update) do
    update
    |> Decoder.apply(transaction)
  end

  def put_pending_structs(
        %Transaction{doc: %Doc{} = doc} = transaction,
        %{structs: _, missing_sv: _} = pending_structs
      ) do
    %{transaction | doc: %{doc | pending_structs: pending_structs}}
  end

  def put_pending_delete_sets(
        %Transaction{doc: %Doc{} = doc} = transaction,
        %{} = pending_delete_sets
      ) do
    %{transaction | doc: %{doc | pending_delete_sets: pending_delete_sets}}
  end

  def get_instance(%Doc{name: name}), do: get_instance(name)

  def get_instance(pid) do
    GenServer.call(pid, :get_instance)
  end

  def handle_call({:get_array, name}, _, doc) do
    case do_get_array(doc, name) do
      {:ok, array, doc} -> {:reply, {:ok, array}, doc}
      {:error, _} = err -> {:reply, err, doc}
    end
  end

  def handle_call({:get_map, name}, _, doc) do
    case do_get_map(doc, name) do
      {:ok, map, doc} -> {:reply, {:ok, map}, doc}
      {:error, _} = err -> {:reply, err, doc}
    end
  end

  def handle_call({:get_text, name}, _, doc) do
    case do_get_text(doc, name) do
      {:ok, text, doc} -> {:reply, {:ok, text}, doc}
      {:error, _} = err -> {:reply, err, doc}
    end
  end

  def handle_call(
        {:transact, f, opts},
        _,
        %Doc{name: name} = doc
      ) do
    origin = Keyword.get(opts, :origin)
    local = Keyword.get(opts, :local, true)

    transaction = Transaction.new(doc, origin, local)

    case f.(transaction) do
      {:ok, %Transaction{} = new_transaction} ->
        new_transaction =
          new_transaction
          |> Transaction.finalize()
          |> Transaction.cleanup()

        {:reply, {:ok, name}, new_transaction.doc}

      error ->
        Logger.warning("Transaction failed in doc #{inspect(doc.name)}")
        {:reply, error, doc}
    end
  end

  def handle_call(:get_instance, _, doc) do
    {:reply, {:ok, doc}, doc}
  end

  defp compose_opts(opts) do
    Keyword.merge(
      [
        name: UUID.uuid4() |> String.to_atom(),
        collection_id: nil,
        gc: true,
        gc_filter: fn -> true end,
        meta: nil,
        autoload: false,
        should_load: true,
        client_id: System.unique_integer([:positive])
      ],
      opts
    )
  end

  # defp replace_recursively(%{name: name}, %{name: name} = with_type), do: with_type

  defp replace_recursively(type, %{name: name} = with_type) do
    type
    |> Type.to_list(with_deleted: true, as_items: true)
    |> Enum.reduce(type, fn
      %Item{content: [%_{name: ^name} = c]} = item, type when c != with_type ->
        case Type.unsafe_replace(type, item, [%Item{item | content: [with_type]}]) do
          {:ok, new_type} -> new_type
          _ -> type
        end

      %Item{content: [%_{} = content]} = item, type ->
        with impl when not is_nil(impl) <- Type.impl_for(content),
             {:ok, new_type} <-
               Type.unsafe_replace(type, item, [
                 %Item{item | content: [replace_recursively(content, with_type)]}
               ]) do
          new_type
        else
          _ -> type
        end

      _item, type ->
        type
    end)
  end

  defp do_get_array(%Doc{share: share} = doc, name) when is_map_key(share, name) do
    case share[name] do
      %Unknown{} = u ->
        array = Array.from_unknown(u)
        doc = %{doc | share: Map.replace(share, name, array)}
        {:ok, array, doc}

      _ ->
        {:error, "Type with the name #{name} has already been added"}
    end
  end

  defp do_get_array(%Doc{} = doc, name) do
    array =
      case name do
        nil -> Array.new(doc)
        _ -> Array.new(doc, name)
      end

    {:ok, array, %Doc{doc | share: Map.put_new(doc.share, name, array)}}
  end

  defp do_get_map(%Doc{share: share} = doc, name) when is_map_key(share, name) do
    case share[name] do
      %Unknown{} = u ->
        map = Y.Type.Map.from_unknown(u)
        {:ok, map, %{doc | share: Map.replace(share, name, map)}}

      _ ->
        {:error, "Type with the name #{name} has already been added"}
    end
  end

  defp do_get_map(%Doc{} = doc, name) do
    map = Y.Type.Map.new(doc, name)
    {:ok, map, %Doc{doc | share: Map.put_new(doc.share, name, map)}}
  end

  defp do_get_text(%Doc{share: share} = doc, name) when is_map_key(share, name) do
    case share[name] do
      %Unknown{} = u ->
        map = Y.Type.Text.from_unknown(u)
        {:ok, map, %{doc | share: Map.replace(share, name, map)}}

      _ ->
        {:error, "Type with the name #{name} has already been added"}
    end
  end

  defp do_get_text(%Doc{} = doc, name) do
    text = Y.Type.Text.new(doc, name)
    {:ok, text, %Doc{doc | share: Map.put_new(doc.share, name, text)}}
  end

  defp do_find_parent(type, child_item) do
    if Type.impl_for(type) do
      type
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.find_value(fn %_{content: content_list} = found ->
        Enum.find_value(content_list, fn content ->
          case Type.impl_for(content) do
            nil ->
              nil

            _ ->
              content
              |> Type.to_list(as_items: true, with_deleted: true)
              |> Enum.find(&(&1 == child_item))
              |> case do
                nil -> do_find_parent(content, child_item)
                _ -> found
              end
          end
        end)
      end)
    end
  end
end
