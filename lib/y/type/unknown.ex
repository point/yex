defmodule Y.Type.Unknown do
  alias __MODULE__
  alias Y.Doc
  alias Y.Type
  alias Y.Item
  alias Y.ID
  alias Y.Transaction

  require Logger

  defstruct doc_name: nil,
            name: nil,
            items: []

  def new(%Doc{name: doc_name}, name) do
    %Unknown{doc_name: doc_name, name: name}
  end

  defimpl Type do
    def highest_clock(%Unknown{items: items}, client_id) do
      case client_id do
        nil -> items
        client_id -> Enum.reject(items, fn %Item{id: %ID{client: cl}} -> cl != client_id end)
      end
      |> Enum.reduce(0, fn %Item{id: %ID{clock: clock}}, acc ->
        max(clock, acc)
      end)
    end

    def highest_clock_with_length(%Unknown{items: items}, client_id) do
      case client_id do
        nil -> items
        client_id -> Enum.reject(items, fn %Item{id: %ID{client: cl}} -> cl != client_id end)
      end
      |> Enum.reduce(0, fn %Item{id: %ID{clock: clock}, length: length}, acc ->
        max(clock + length, acc)
      end)
    end

    def highest_clock_by_client_id(%Unknown{items: items}) do
      Enum.reduce(items, %{}, fn item, acc ->
        Map.update(acc, item.id.client, item.id.clock, fn existing ->
          max(existing, item.id.clock)
        end)
      end)
    end

    def highest_clock_with_length_by_client_id(%Unknown{items: items}) do
      Enum.reduce(items, %{}, fn item, acc ->
        Map.update(acc, item.id.client, item.id.clock + Item.content_length(item), fn existing ->
          max(existing, item.id.clock + Item.content_length(item))
        end)
      end)
    end

    def pack(%Unknown{items: items} = type) do
      new_items =
        items
        |> Enum.reduce([], fn
          e, [] ->
            [e]

          e, [%Item{} = head | tail] = acc ->
            if Item.mergeable?(head, e) do
              [Item.merge!(head, e) | tail]
            else
              [e | acc]
            end
        end)
        |> Enum.reverse()

      %{type | items: new_items}
    end

    def to_list(%Unknown{items: items}, opts \\ []) do
      as_items = Keyword.get(opts, :as_items, false)
      with_deleted = Keyword.get(opts, :with_deleted, false)

      items = if with_deleted, do: items, else: Enum.reject(items, & &1.deleted?)
      if as_items, do: items, else: items |> Enum.flat_map(& &1.content)
    end

    def find(%Unknown{items: items}, %ID{} = id, default \\ nil),
      do: items |> Enum.find(default, &(&1.id == id))

    def unsafe_replace(
          %Unknown{items: items} = type,
          %Item{id: %ID{clock: item_clock}} = item,
          with_items
        )
        when is_list(with_items) do
      [%{id: %ID{clock: f_clock}} | _] = with_items

      with_items_length =
        Enum.reduce(with_items, 0, fn i, acc -> acc + Item.content_length(i) end)

      cond do
        f_clock != item_clock ->
          {:error, "Clocks diverge"}

        Item.content_length(item) != with_items_length ->
          {:error, "Total content length of items != length of item to replace"}

        :otherwise ->
          case Enum.find_index(items, &(&1 == item)) do
            nil ->
              {:error, "Item not found in items"}

            index ->
              {:ok, %{type | items: List.flatten(List.replace_at(items, index, with_items))}}
          end
      end
    end

    def between(%Unknown{items: items}, %ID{} = left, %ID{} = right) do
      items
      |> Enum.reduce_while({[], false}, fn
        %{id: ^left} = item, {acc, false} ->
          {:cont, {[item | acc], true}}

        %{id: ^right} = item, {acc, true} ->
          {:halt, {[item | acc], false}}

        item, {acc, true} ->
          {:cont, {[item | acc], true}}

        _, {[] = acc, false} ->
          {:cont, {acc, false}}

        _, {acc, _} ->
          {:halt, {acc, false}}
      end)
      |> elem(0)
      |> Enum.reverse()
    end

    def add_after(%Unknown{items: items} = type, %Item{} = after_item, %Item{} = item) do
      case Enum.find_index(items, &(&1 == after_item)) do
        nil -> {:error, "After item not found"}
        index -> {:ok, %{type | items: List.insert_at(items, index + 1, item)}}
      end
    end

    def add_before(%Unknown{items: items} = type, nil, %Item{} = item),
      do: {:ok, %{type | items: [item | items]}}

    def add_before(%Unknown{items: items} = type, %Item{} = before_item, %Item{} = item) do
      case Enum.find_index(items, &(&1 == before_item)) do
        nil -> {:error, "Before item not found"}
        index -> {:ok, %{type | items: List.insert_at(items, index, item)}}
      end
    end

    def delete(%Unknown{items: items} = type, %Transaction{} = transaction, %ID{} = id) do
      case Enum.find(items, &(&1.id == id)) do
        nil ->
          Logger.warning("Fail to find item to delete", items: items, id: id)
          {:ok, transaction}

        %Item{} = item ->
          Transaction.update(transaction, %Unknown{type | items: List.delete(items, item)})
      end
    end

    def next(%Unknown{items: items}, %Item{} = item) do
      case Enum.chunk_by(items, fn i -> i == item end) do
        [_, _, [n | _]] -> n
        _ -> nil
      end
    end

    def prev(%Unknown{items: items}, %Item{} = item) do
      case Enum.chunk_by(items, fn i -> i == item end) do
        [l, _, _] -> List.last(l)
        _ -> nil
      end
    end

    def first(%Unknown{items: []}, _), do: nil
    def first(%Unknown{items: [h | _]}, _), do: h

    def last(%Unknown{items: []}, _), do: nil
    def last(%Unknown{items: items}, _), do: List.last(items)

    def type_ref(_), do: -1
  end
end
