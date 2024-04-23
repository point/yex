defmodule Y.Doc do
  alias __MODULE__
  alias Y.Type
  alias Y.ID
  alias Y.Item
  alias Y.Type.Array
  alias Y.Type.Unknown
  alias Y.Transaction
  alias Y.Decoder

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
            client_id: System.unique_integer([:positive]),
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
      should_load: opts[:should_load]
    }

    {:ok, doc}
  end

  def new(opts \\ []) do
    with {:ok, pid} <- start_link(opts),
         {:ok, %Doc{name: name}} <- get_instance(pid) do
      {:ok, name}
    end
  end

  def get_array(doc_name, array_name \\ "") do
    GenServer.call(doc_name, {:get_array, array_name})
  end

  def get_map(doc_name, map_name \\ "") do
    GenServer.call(doc_name, {:get_map, map_name})
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

  def get_or_create_unknown(%Transaction{doc: doc} = transaction, name) do
    case get(transaction, name) do
      {:ok, type} ->
        {:ok, type, transaction}

      {:error, _} ->
        type = Unknown.new(doc, name)
        {:ok, type, %{transaction | doc: %Doc{doc | share: Map.put_new(doc.share, name, type)}}}
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

  def items_of_client!(%Doc{} = doc, client) do
    doc.share
    |> Map.values()
    |> Enum.flat_map(fn type ->
      type
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.filter(fn %_{id: %ID{client: c}} -> c == client end)
      |> Enum.sort_by(fn %_{id: %ID{clock: clock}} -> clock end)
    end)
  end

  def type_with_id!(%Doc{} = doc, %ID{} = id) do
    doc.share
    |> Map.values()
    |> Enum.filter(fn type -> Type.highest_clock_with_length(type) >= id.clock end)
    |> Enum.find(fn type ->
      type
      |> Type.to_list(as_items: true)
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

  def pack!(%Doc{share: share} = doc) do
    # TODO Pack delete_set
    share =
      share
      |> Enum.map(fn {name, type} ->
        {name, Type.pack(type)}
      end)
      |> Enum.into(%{})

    %{doc | share: share}
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

  def handle_call({:get_array, name}, _, %{share: share} = doc) when is_map_key(share, name) do
    case share[name] do
      %Unknown{} = u ->
        array = Array.from_unknown(u)
        {:reply, {:ok, array}, %{doc | share: Map.replace(share, name, array)}}

      _ ->
        {:reply, {:error, "Type with the name #{name} has already been added"}, doc}
    end
  end

  def handle_call({:get_array, array_name}, _, %{share: share} = doc) do
    array = Array.new(doc, array_name)

    {:reply, {:ok, array}, %Doc{doc | share: Map.put_new(share, array_name, array)}}
  end

  def handle_call({:get_map, name}, _, %{share: share} = doc) when is_map_key(share, name) do
    case share[name] do
      %Unknown{} = u ->
        map = Y.Type.Map.from_unknown(u)
        {:reply, {:ok, map}, %{doc | share: Map.replace(share, name, map)}}

      _ ->
        {:reply, {:error, "Type with the name #{name} has already been added"}, doc}
    end
  end

  def handle_call({:get_map, map_name}, _, %{share: share} = doc) do
    map = Y.Type.Map.new(doc, map_name)

    {:reply, {:ok, map}, %Doc{doc | share: Map.put_new(share, map_name, map)}}
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
        should_load: true
      ],
      opts
    )
  end

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
        with impl when is_atom(impl) <- Type.impl_for(item),
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
end
