defmodule Y.Type.Map do
  alias Y.Transaction
  alias Y.Type
  alias Y.Type.Unknown
  alias Y.Content.Deleted
  alias Y.Doc
  alias Y.Item
  alias Y.ID

  require Logger

  defstruct map: %{},
            doc_name: nil,
            name: nil

  def new(%Doc{name: doc_name}, name \\ UUID.uuid4()) do
    %Y.Type.Map{doc_name: doc_name, name: name}
  end

  def put({:ok, %Y.Type.Map{} = map_type, %Transaction{} = transaction}, key, content),
    do: put(map_type, transaction, key, content)

  def put(
        %Y.Type.Map{map: map, name: parent_name} = map_type,
        %Transaction{} = transaction,
        key,
        content
      ) do
    # Must get clock for THIS client only, not the max across all clients
    clock_length = Doc.highest_clock_with_length(transaction, transaction.doc.client_id)

    item =
      Item.new(
        id: ID.new(transaction.doc.client_id, clock_length),
        content: [content],
        parent_name: parent_name,
        parent_sub: key
      )

    new_map =
      Map.update(map, key, [item], fn [active_item | rest] ->
        # origin (thus ID to the left) because items are in reversed order
        # `item` would be to the right of the last element
        item = %{item | origin: active_item.id}
        old_active = Item.delete(active_item)
        [item | [old_active | rest]]
      end)

    new_map_type = %{map_type | map: new_map}

    case Transaction.update(transaction, new_map_type) do
      {:ok, transaction} -> {:ok, new_map_type, transaction}
      err -> err
    end
  end

  def get(%Y.Type.Map{map: map}, key, default \\ nil) do
    case Map.fetch(map, key) do
      {:ok, [%Item{deleted?: false, content: [content]} | _]} -> content
      _ -> default
    end
  end

  def get_item(%Y.Type.Map{map: map}, key, default \\ nil) do
    case Map.fetch(map, key) do
      {:ok, [%Item{} = item | _]} -> item
      _ -> default
    end
  end

  def has_key?(%Y.Type.Map{map: map}, key) do
    case Map.fetch(map, key) do
      {:ok, [%Item{deleted?: false} | _]} -> true
      _ -> false
    end
  end

  def keys(%Y.Type.Map{map: map}) do
    map
    |> Enum.reduce([], fn {k, v}, acc ->
      case v do
        [%Item{deleted?: false} | _] -> [k | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  def from_unknown(%Unknown{} = u) do
    map =
      u
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.reduce(%{}, fn
        %Item{parent_sub: nil}, map -> map
        item, map -> Map.update(map, item.parent_sub, [item], fn items -> [item | items] end)
      end)
      |> Enum.map(fn {k, items} ->
        {deleted, [live | _]} = Enum.split_with(items, & &1.deleted?)
        {k, [live | deleted]}
      end)
      |> Enum.into(%{})

    %Y.Type.Map{doc_name: u.doc_name, name: u.name, map: map}
  end

  def delete(%Y.Type.Map{map: map} = map_type, transaction, key) do
    with %Item{deleted?: false} = item <- get_item(map_type, key),
         deleted_item <- Item.delete(item),
         new_map_type = %{
           map_type
           | map: Map.update!(map, key, fn [_ | rest] -> [deleted_item | rest] end)
         },
         {:ok, transaction} <-
           Transaction.update(transaction, new_map_type) do
      {:ok, new_map_type, transaction}
    else
      %Item{deleted?: true} ->
        Logger.info("Item already deleted",
          map: map,
          key: key
        )

        {:ok, map, transaction}

      err ->
        Logger.warning("Fail to delete map item by key #{inspect(key)}. Error: #{inspect(err)}",
          map: map,
          key: key
        )

        {:error, map, transaction}
    end
  end

  defdelegate to_list(array), to: Type
  defdelegate to_list(array, opts), to: Type

  defimpl Type do
    def highest_clock(%Y.Type.Map{map: map}, client_id) do
      map
      |> Map.values()
      |> then(fn items ->
        case client_id do
          nil -> items
          client_id -> Enum.reject(items, fn %Item{id: %ID{client: cl}} -> cl != client_id end)
        end
      end)
      |> Enum.reduce(0, fn %Item{id: %ID{clock: clock}}, acc ->
        max(clock, acc)
      end)
    end

    def highest_clock_with_length(%Y.Type.Map{map: map}, client_id) do
      map
      |> Map.values()
      |> List.flatten()
      |> then(fn items ->
        case client_id do
          nil -> items
          client_id -> Enum.reject(items, fn %Item{id: %ID{client: cl}} -> cl != client_id end)
        end
      end)
      |> Enum.reduce(0, fn %Item{id: %ID{clock: clock}, length: length}, acc ->
        max(clock + length, acc)
      end)
    end

    def highest_clock_by_client_id(%Y.Type.Map{map: map}) do
      map
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(%{}, fn item, acc ->
        Map.update(acc, item.id.client, item.id.clock, fn existing ->
          max(existing, item.id.clock)
        end)
      end)
    end

    def highest_clock_with_length_by_client_id(%Y.Type.Map{map: map}) do
      map
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(%{}, fn item, acc ->
        Map.update(acc, item.id.client, item.id.clock + Item.content_length(item), fn existing ->
          max(existing, item.id.clock + Item.content_length(item))
        end)
      end)
    end

    def pack(%Y.Type.Map{map: map} = map_type) do
      new_map =
        map
        |> Enum.map(fn {k, items} ->
          {k,
           Enum.reduce(Enum.reverse(items), [], fn
             e, [] ->
               [e]

             e, [%Item{} = head | tail] = acc ->
               if Item.mergeable?(head, e) do
                 [Item.merge!(head, e) | tail]
               else
                 [e | acc]
               end
           end)}
        end)
        |> Enum.into(%{})

      %{map_type | map: new_map}
    end

    def to_list(%Y.Type.Map{map: map}, opts \\ []) do
      as_items = Keyword.get(opts, :as_items, false)
      with_deleted = Keyword.get(opts, :with_deleted, false)

      items =
        map
        |> Enum.reduce([], fn {_k, v}, acc ->
          case v do
            [%Item{} = item | _] -> [item | acc]
            _ -> acc
          end
        end)

      items =
        if with_deleted do
          items
        else
          items |> Enum.reject(& &1.deleted?)
        end

      if as_items,
        do: items,
        else:
          items
          |> Enum.map(fn %Item{parent_sub: parent_sub, content: [content | _]} ->
            {parent_sub, content}
          end)
    end

    def find(%Y.Type.Map{map: map}, %ID{} = id, default) do
      map
      |> Map.values()
      |> List.flatten()
      |> Enum.find(default, fn %Item{id: i_id} -> i_id == id end)
    end

    def unsafe_replace(_, %Item{parent_sub: nil}, _), do: {:error, "Item has no parent_sub set"}

    def unsafe_replace(
          %Y.Type.Map{map: map} = map_type,
          %Item{id: %ID{clock: item_clock}, parent_sub: parent_sub} = item,
          with_items
        )
        when is_list(with_items) do
      [%{id: %ID{clock: f_clock}} | _] = with_items

      with_items_length =
        Enum.reduce(with_items, 0, fn i, acc -> acc + Item.content_length(i) end)

      with_items_parent_sub = Enum.map(with_items, & &1.parent_sub) |> Enum.uniq()

      cond do
        f_clock != item_clock ->
          {:error, "Clocks diverge"}

        Item.content_length(item) != with_items_length ->
          {:error, "Total content length of items != length of item to replace"}

        Map.has_key?(map, parent_sub) == false ->
          {:error, "Item's parent_sub key is missing in the map"}

        [parent_sub] != with_items_parent_sub ->
          {:error,
           "Some item(s) to replace has different parent_sub than the item to be replaced"}

        :otherwise ->
          new_map =
            Map.update!(map, parent_sub, fn items ->
              items
              |> Enum.reverse()
              |> Enum.flat_map(fn next_item ->
                if next_item == item, do: with_items, else: [next_item]
              end)
            end)

          if Map.fetch!(new_map, parent_sub) == Map.fetch!(map, parent_sub) do
            {:error, "Item not found"}
          else
            {:ok, %{map_type | map: new_map}}
          end
      end
    end

    def between(%Y.Type.Map{map: map}, %ID{} = left, %ID{} = right) do
      Enum.reduce_while(map, [], fn {_, items}, _ ->
        items
        |> Enum.reverse()
        |> Enum.reduce_while([], fn
          item, [] when item == left -> {:cont, [item]}
          item, [] when item != left -> {:cont, []}
          item, i_acc when item == right -> {:halt, [item | i_acc]}
          item, i_acc when item != right -> {:cont, [item | i_acc]}
        end)
        |> case do
          [] -> {:cont, []}
          acc -> {:halt, Enum.reverse(acc)}
        end
      end)
    end

    def add_after(_, %Item{parent_sub: ps1}, %Item{parent_sub: ps2}) when ps1 != ps2,
      do: {:error, "Items' parent_sub deffers"}

    def add_after(
          %Y.Type.Map{map: map} = map_type,
          %Item{parent_sub: parent_sub} = after_item,
          %Item{} = item
        ) do
      new_map =
        Map.update!(map, parent_sub, fn items ->
          items
          |> Enum.reverse()
          |> Enum.flat_map(fn next_item ->
            if next_item == after_item, do: [next_item, item], else: [next_item]
          end)
        end)

      if Map.fetch!(new_map, parent_sub) == Map.fetch!(map, parent_sub) do
        {:error, "Item not found"}
      else
        {:ok, %{map_type | map: new_map}}
      end
    end

    def add_before(_, %Item{parent_sub: ps1}, %Item{parent_sub: ps2}) when ps1 != ps2,
      do: {:error, "Items' parent_sub deffers"}

    def add_before(
          %Y.Type.Map{map: map} = map_type,
          %Item{parent_sub: parent_sub} = before_item,
          %Item{} = item
        ) do
      new_map =
        Map.update!(map, parent_sub, fn items ->
          items
          |> Enum.reverse()
          |> Enum.flat_map(fn next_item ->
            if next_item == before_item, do: [item, next_item], else: [next_item]
          end)
        end)

      if Map.fetch!(new_map, parent_sub) == Map.fetch!(map, parent_sub) do
        {:error, "Item not found"}
      else
        {:ok, %{map_type | map: new_map}}
      end
    end

    def add_before(
          %Y.Type.Map{map: map} = map_type,
          nil,
          %Item{parent_sub: parent_sub} = item
        )
        when not is_nil(parent_sub) do
      new_map =
        Map.update(map, parent_sub, [item], fn items -> [item | items] end)

      {:ok, %{map_type | map: new_map}}
    end

    def next(%Item{parent_sub: nil}), do: nil

    def next(%Y.Type.Map{map: map}, %Item{parent_sub: parent_sub} = item) do
      map
      |> Map.get(parent_sub, [])
      |> Enum.reverse()
      |> Enum.reduce_while(nil, fn
        i_item, nil when i_item == item -> {:cont, :take_this}
        _i_item, nil -> {:cont, nil}
        i_item, :take_this -> {:halt, i_item}
      end)
      |> case do
        %Item{} = f -> f
        _ -> nil
      end
    end

    def prev(%Item{parent_sub: nil}), do: nil

    def prev(%Y.Type.Map{map: map}, %Item{parent_sub: parent_sub} = item) do
      map
      |> Map.get(parent_sub, [])
      # no reverse
      |> Enum.reduce_while(nil, fn
        i_item, nil when i_item == item -> {:cont, :take_this}
        _i_item, nil -> {:cont, nil}
        i_item, :take_this -> {:halt, i_item}
      end)
      |> case do
        %Item{} = f -> f
        _ -> nil
      end
    end

    def first(_, %Item{parent_sub: nil}), do: nil

    def first(%Y.Type.Map{} = map_type, %Item{parent_sub: parent_sub}) do
      Map.get(map_type, parent_sub)
    end

    def last(_, %Item{parent_sub: nil}), do: nil

    def last(%Y.Type.Map{} = map_type, %Item{parent_sub: parent_sub}) do
      Map.get(map_type, parent_sub)
    end

    defdelegate delete(map_type, transaction, key), to: Y.Type.Map, as: :delete

    def type_ref(_), do: 1

    def gc(%Y.Type.Map{map: map} = type_map) do
      new_map =
        map
        |> Enum.reduce([], fn {k, v}, acc ->
          case v do
            [%Item{deleted?: false} | _] ->
              [{k, v} | acc]

            [%Item{content: [%Deleted{}]} | _] ->
              [{k, v} | acc]

            [%Item{} = item | rest] ->
              [{k, [%{item | content: [Deleted.from_item(item)]} | rest]} | acc]
          end
        end)
        |> Enum.into(%{})

      %{type_map | map: new_map}
    end
  end
end
