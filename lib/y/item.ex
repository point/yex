defmodule Y.Item do
  alias __MODULE__
  alias Y.ID
  alias Y.Doc
  alias Y.Transaction
  alias Y.Type
  alias Y.Skip
  alias Y.Content.Binary

  require Logger

  defstruct id: %ID{},
            length: 0,
            content: nil,
            origin: nil,
            right_origin: nil,
            parent_name: nil,
            parent_sub: nil,
            deleted?: false,
            keep?: true

  def new(opts \\ []) do
    %ID{} = id = Keyword.fetch!(opts, :id)
    content = Keyword.fetch!(opts, :content)
    origin = Keyword.get(opts, :origin)
    right_origin = Keyword.get(opts, :right_origin)
    parent_name = Keyword.get(opts, :parent_name)
    parent_sub = Keyword.get(opts, :parent_sub)

    item = %Item{
      id: id,
      content: content,
      origin: origin,
      right_origin: right_origin,
      parent_name: parent_name,
      parent_sub: parent_sub
    }

    %{item | length: content_length(item)}
  end

  def valid?(%Item{} = item, %Transaction{} = transaction) do
    valid_origin?(transaction, item) && valid_right_origin?(transaction, item) &&
      valid_parent?(transaction, item)
  end

  def content_length(%Item{deleted?: true}), do: 0
  def content_length(%Item{content: content}) when is_list(content), do: length(content)
  def content_length(%Item{}), do: 1
  def content_length(%Skip{length: len}), do: len

  def id(nil), do: nil
  def id(%Item{id: id}), do: id
  def last_id(%Item{content: [_], id: id}), do: id

  def last_id(%Item{id: id} = item) do
    ID.new(id.client, id.clock + content_length(item) - 1)
  end

  def maybe_offset(%Item{} = item, 0, transaction), do: {:ok, item, transaction}

  def maybe_offset(%Item{length: length} = item, offset, transaction)
      when offset > 0 and offset < length do
    new_content =
      if is_list(item.content), do: Enum.slice(item.content, offset), else: item.content

    with id = ID.new(item.id.client, item.id.clock + offset - 1),
         {:ok, transaction} <- maybe_split_left(item, id, transaction),
         item = %Item{
           item
           | id: %{id | clock: id.clock + offset},
             content: new_content,
             length: content_length(new_content)
         } do
      {:ok, item, transaction}
    end
  end

  def split(%Item{content: content} = item, at_index)
      when at_index >= 0 and at_index < length(content) do
    {content_l, content_r} = Enum.split(content, at_index)
    length_l = length(content_l)
    length_r = length(content_r)

    right_id = ID.new(item.id.client, item.id.clock + length_l)

    item_l = %{
      item
      | length: length_l,
        content: content_l,
        origin: item.origin,
        right_origin: nil
    }

    item_r = %{
      item
      | length: length_r,
        content: content_r,
        id: right_id,
        origin: last_id(item_l),
        right_origin: item.right_origin
    }

    {item_l, item_r}
  end

  def mergeable?(%Item{deleted?: d1}, %Item{deleted?: d2}) when d1 != d2, do: false

  def mergeable?(%Item{} = item1, %Item{} = item2) do
    [f1 | _] = item1.content
    [f2 | _] = item2.content

    if is_struct(f1) || is_struct(f2) do
      is_struct(f1) && is_struct(f2) && f1.__struct__ == f2.__struct
    else
      # && ID.equal?(item1.right_origin, item2.right_origin)
      !is_struct(f1) && !is_struct(f2)
    end
    |> Kernel.&&(ID.equal?(item2.origin, Item.last_id(item1)))
    |> Kernel.&&(ID.equal?(item1.right_origin, item2.right_origin))
    |> Kernel.&&(item1.id.client == item2.id.client)
    |> Kernel.&&(item1.id.clock + Item.content_length(item1) == item2.id.clock)
  end

  def mergeable?(_, _), do: false

  def merge!(%Item{} = item1, %Item{} = item2) do
    if mergeable?(item1, item2) do
      %Item{
        item1
        | content: item1.content ++ item2.content,
          length: item1.length + item2.length,
          right_origin: item2.right_origin
      }
    else
      raise "cannot merge unmerable items"
    end
  end

  def content_ref(%Item{content: content}) do
    cond do
      match?([%Binary{}], content) -> 3
      is_struct(content) -> 9
      :otherwise -> 8
    end
  end

  def integrate(%Item{parent_name: %ID{} = item_of_parent_id} = item, transaction, offset) do
    with true <- valid?(item, transaction),
         %Item{content: [%_{name: parent_name}]} <- Doc.find_item(transaction, item_of_parent_id) do
      integrate(%{item | parent_name: parent_name}, transaction, offset)
    else
      %Y.GC{} -> integrate(%{item | parent_name: nil}, transaction, offset)
      false -> {:invalid, item}
      _ -> {:error, "Cannot integrate item"}
    end
  end

  def integrate(%Item{parent_name: nil} = item, transaction, offset) do
    if valid?(item, transaction) do
      left = item.origin && Doc.find_item(transaction, item.origin)
      right = item.right_origin && Doc.find_item(transaction, item.right_origin)

      cond do
        left && left.parent_name ->
          integrate(
            %{item | parent_name: left.parent_name, parent_sub: left.parent_sub},
            transaction,
            offset
          )

        right && right.parent_name ->
          integrate(
            %{item | parent_name: right.parent_name, parent_sub: right.parent_sub},
            transaction,
            offset
          )

        :otherwise ->
          {:error, "Cannot integrate item. Left item or right item missing"}
      end
    else
      {:invalid, transaction}
    end
  end

  def integrate(%Item{} = item, %Transaction{} = transaction, offset) do
    with true <- valid?(item, transaction),
         %{parent_name: parent_name} when not is_nil(parent_name) <- item,
         {:ok, transaction} <- maybe_split_left(item, item.origin, transaction),
         {:ok, transaction} <- maybe_split_right(item, item.right_origin, transaction),
         {:ok, item, transaction} <- maybe_offset(item, offset, transaction),
         {:ok, type, transaction} <- Doc.get_or_create_unknown(transaction, parent_name) do
      with %Item{} = l <- find_left_for(item, type, transaction),
           {:ok, updated_type} <- Type.add_after(type, l, item),
           {:ok, _transaction} = res <- Transaction.update(transaction, updated_type) do
        res
      else
        false ->
          {:invalid, transaction}

        nil ->
          case Type.add_before(type, Type.first(type, item), item) do
            {:ok, updated_type} ->
              Transaction.update(transaction, updated_type)

            _ ->
              Logger.warning("Failed to execute add_before", type: type, item: item)
              {:error, "Failed to insert item"}
          end

        err ->
          Logger.warning("Failed to execute add_before", type: type, item: item, error: err)
          {:error, "Failed to insert item"}
      end
    end
  end

  def explode(%Item{length: 1} = item), do: [item]

  def explode(%Item{} = item) do
    {acc, item_to_add} =
      Enum.reduce(2..Item.content_length(item)//1, {[], item}, fn _, {acc, item} ->
        {item_l, item_r} = split(item, 1)
        {[item_l | acc], item_r}
      end)

    Enum.reverse([item_to_add | acc])
  end

  def delete(%Item{deleted?: true} = item), do: item
  def delete(%Item{} = item), do: %Item{item | deleted?: true}

  defp valid_origin?(_, %{origin: nil}), do: true

  defp valid_origin?(%Transaction{} = transaction, %Item{origin: origin, id: id}) do
    not (origin.client != id.client &&
           origin.clock >= Doc.highest_clock_with_length(transaction, origin.client))
  end

  defp valid_right_origin?(_, %{right_origin: nil}), do: true

  defp valid_right_origin?(%Transaction{} = transaction, %Item{right_origin: right_origin, id: id}) do
    not (right_origin.client != id.client &&
           right_origin.clock >= Doc.highest_clock_with_length(transaction, right_origin.client))
  end

  defp valid_parent?(_, %{parent_name: nil}), do: true

  defp valid_parent?(%Transaction{} = transaction, %{
         parent_name: %ID{client: client, clock: clock},
         id: id
       }) do
    client == id.client && clock < Doc.highest_clock_with_length(transaction, client)
  end

  defp valid_parent?(_, _), do: true

  defp maybe_split_left(_, nil, transaction), do: {:ok, transaction}

  defp maybe_split_left(%Item{parent_name: parent_name}, %ID{} = id, transaction) do
    with %Item{} = left <- Doc.find_item(transaction, parent_name, id),
         {:ok, type} <- Doc.get(transaction, parent_name) do
      if id.clock == left.id.clock + content_length(left) - 1 do
        {:ok, transaction}
      else
        split_and_replace_left(type, left, id, transaction)
      end
    end
  end

  defp split_and_replace_left(type, %Item{} = left, %ID{} = id, %Transaction{} = transaction) do
    with {l, r} <- split(left, id.clock - left.id.clock + 1),
         {:ok, new_type} <- Type.unsafe_replace(type, left, [l, r]),
         {:ok, _transaction} = res <- Transaction.update(transaction, new_type) do
      res
    end
  end

  defp maybe_split_right(_, nil, transaction), do: {:ok, transaction}

  defp maybe_split_right(%Item{parent_name: parent_name}, %ID{} = id, transaction) do
    with %Item{} = right <- Doc.find_item(transaction, parent_name, id),
         {:ok, type} <- Doc.get(transaction, parent_name) do
      if id.clock == right.id.clock do
        {:ok, transaction}
      else
        split_and_replace_right(type, right, id, transaction)
      end
    end
  end

  defp split_and_replace_right(type, %Item{} = right, %ID{} = id, %Transaction{} = transaction) do
    with {l, r} <- split(right, id.clock - right.id.clock),
         {:ok, new_type} <- Type.unsafe_replace(type, right, [l, r]),
         {:ok, _transaction} = res <- Transaction.update(transaction, new_type) do
      res
    end
  end

  defp find_left_for(item, type, transaction) do
    item_left =
      with %ID{} <- item.origin,
           %Item{} = left <- Doc.find_item(transaction, item.parent_name, item.origin) do
        left
      end

    item_right =
      with %ID{} <- item.right_origin,
           %Item{} = right <- Doc.find_item(transaction, item.parent_name, item.right_origin) do
        right
      end

    if (item_left == nil && (item_right == nil || Type.prev(type, item_right) != nil)) ||
         (item_left != nil && Type.next(type, item_left) != item_right) do
      start_range =
        with %Item{} <- item_left,
             %Item{} = o <- Type.next(type, item_left) do
          o
        else
          _ -> Type.first(type, item)
        end

      end_range =
        case item_right do
          %Item{} -> item_right
          _ -> Type.last(type, item)
        end

      with %Item{} <- start_range,
           %Item{} <- end_range do
        do_find_left_for(
          item,
          nil,
          Type.between(type, start_range.id, end_range.id),
          transaction,
          type,
          [],
          []
        )
      end
    else
      item_left
    end
  end

  defp do_find_left_for(_, item_found, [], _, _, _, _), do: item_found

  defp do_find_left_for(
         %Item{} = item,
         item_found,
         [o | rest_in_range],
         transaction,
         type,
         conflicting_items,
         items_before_origin
       ) do
    cond do
      ID.equal?(item.origin, o.origin) ->
        cond do
          o.id.client < item.id.client ->
            do_find_left_for(item, o, rest_in_range, transaction, type, [], [
              o | items_before_origin
            ])

          ID.equal?(item.right_origin, o.right_origin) ->
            item_found

          :otherwise ->
            do_find_left_for(
              item,
              item_found,
              rest_in_range,
              transaction,
              type,
              [o | conflicting_items],
              [o | items_before_origin]
            )
        end

      o.origin != nil && Doc.find_item(transaction, type.name, o.origin) in items_before_origin ->
        cond do
          Doc.find_item(transaction, type.name, o.origin) not in conflicting_items ->
            do_find_left_for(item, o, rest_in_range, transaction, type, [], [
              o | items_before_origin
            ])

          :otherwise ->
            do_find_left_for(
              item,
              item_found,
              rest_in_range,
              transaction,
              type,
              [o | conflicting_items],
              [o | items_before_origin]
            )
        end

      :otherwise ->
        item_found
    end
  end
end
