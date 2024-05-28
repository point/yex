defmodule Y.Type.Text.Tree do
  alias __MODULE__
  alias FingerTree.EmptyTree
  alias Y.Content.Format
  alias Y.Item
  alias Y.ID

  defstruct [:ft]
  @type t() :: %Tree{ft: FingerTree.t()}

  defmodule Meter do
    @enforce_keys [:highest_clocks, :highest_clocks_with_length, :len]
    defstruct highest_clocks: %{}, highest_clocks_with_length: %{}, len: 0
  end

  use Y.Type.GeneralTree, mod: Tree

  def new do
    %Tree{ft: FingerTree.finger_tree(meter_object())}
  end

  def insert(%Tree{} = tree, index, text, attributes, parent_name, client_id, last_clock) do
    %Meter{len: tree_len} = FingerTree.measure(tree.ft)

    ft =
      cond do
        index <= 0 ->
          do_insert(
            FingerTree.finger_tree(meter_object()),
            tree.ft,
            text,
            attributes,
            parent_name,
            client_id,
            last_clock
          )

        index >= tree_len ->
          do_insert(
            tree.ft,
            FingerTree.finger_tree(meter_object()),
            text,
            attributes,
            parent_name,
            client_id,
            last_clock
          )

        :otherwise ->
          {l, v, r} =
            FingerTree.split(tree.ft, fn %{len: len} ->
              index <= len
            end)

          %Meter{len: len_l} = FingerTree.measure(l)

          cond do
            len_l == index ->
              do_insert(
                l,
                FingerTree.cons(r, v),
                text,
                attributes,
                parent_name,
                client_id,
                last_clock
              )

            len_l + Item.content_length(v) == index ->
              do_insert(
                FingerTree.conj(l, v),
                r,
                text,
                attributes,
                parent_name,
                client_id,
                last_clock
              )

            len_l < index and index < len_l + v.length ->
              diff = index - len_l
              {split_l, split_r} = Item.split(v, diff)

              do_insert(
                FingerTree.conj(l, split_l),
                FingerTree.cons(r, split_r),
                text,
                attributes,
                parent_name,
                client_id,
                last_clock
              )
          end
      end

    %{tree | ft: ft}
  end

  def delete(%Tree{} = tree, index, length) do
    {l, v, r} =
      FingerTree.split(tree.ft, fn %{len: len} ->
        index <= len
      end)

    %Meter{len: len_l} = FingerTree.measure(l)

    {l, collected_items_reverse, right_tree, gathered_attributes} =
      cond do
        len_l == index ->
          do_delete([], FingerTree.cons(r, v), length, %{})
          |> Tuple.insert_at(0, l)

        len_l + Item.content_length(v) == index ->
          do_delete([], r, length, %{})
          |> Tuple.insert_at(0, FingerTree.conj(l, v))
      end

    left_gathered_attributes = gather_attributes(l)

    r =
      collected_items_reverse
      |> Enum.reduce(right_tree, fn
        %Item{deleted?: true} = item, r ->
          FingerTree.cons(r, item)

        %Item{content: [%Format{key: key, value: value}]} = item, r ->
          if Map.get(gathered_attributes, key) != value ||
               Map.get(left_gathered_attributes, key) == value do
            FingerTree.cons(r, Item.delete(item))
          else
            FingerTree.cons(r, item)
          end

        item, r ->
          FingerTree.cons(r, item)
      end)

    %{tree | ft: FingerTree.append(l, r)}
  end

  defp do_insert(
         left_tree,
         right_tree,
         text,
         attributes,
         parent_name,
         client_id,
         last_clock
       ) do
    gathered_attributes = gather_attributes(left_tree)

    attributes =
      if attributes == %{} do
        gathered_attributes
      else
        attributes
      end

    attributes =
      Enum.reduce(gathered_attributes, attributes, fn
        {k, _}, acc when is_map_key(acc, k) -> acc
        {k, _}, acc -> Map.put(acc, k, nil)
      end)

    with {left_tree, right_tree, gathered_attributes} <-
           minimize_attribute_changes(left_tree, right_tree, gathered_attributes, attributes),
         {negated_attrs, left_tree, right_tree, last_clock} <-
           insert_attributes(
             attributes,
             gathered_attributes,
             left_tree,
             right_tree,
             parent_name,
             client_id,
             last_clock
           ),
         {left_tree, last_clock} <-
           do_insert_text(text, left_tree, right_tree, parent_name, client_id, last_clock),
         {left_tree, right_tree} <-
           insert_negated_attributes(
             negated_attrs,
             left_tree,
             right_tree,
             parent_name,
             client_id,
             last_clock
           ) do
      FingerTree.append(left_tree, right_tree)
    end
  end

  defp gather_attributes(tree), do: do_gather_attributes(tree, %{})

  defp do_gather_attributes(%FingerTree.EmptyTree{} = _, acc) do
    acc
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp do_gather_attributes(tree, acc) do
    case FingerTree.first(tree) do
      %Item{content: [%Format{} = format]} ->
        do_gather_attributes(FingerTree.rest(tree), Map.merge(acc, Format.to_map(format)))

      _ ->
        do_gather_attributes(FingerTree.rest(tree), acc)
    end
  end

  defp minimize_attribute_changes(
         left_tree,
         %FingerTree.EmptyTree{} = right_tree,
         gathered_attributes,
         _attributes
       ),
       do: {left_tree, right_tree, gathered_attributes}

  defp minimize_attribute_changes(left_tree, right_tree, gathered_attributes, attributes) do
    case FingerTree.first(right_tree) do
      %Item{deleted?: true} = item ->
        minimize_attribute_changes(
          FingerTree.conj(left_tree, item),
          FingerTree.rest(right_tree),
          gathered_attributes,
          attributes
        )

      %Item{content: [%Format{key: key, value: value}]} = item ->
        if Map.get(attributes, key) == value do
          minimize_attribute_changes(
            FingerTree.conj(left_tree, item),
            FingerTree.rest(right_tree),
            if(value == nil,
              do: Map.delete(gathered_attributes, key),
              else: Map.put(gathered_attributes, key, value)
            ),
            attributes
          )
        else
          {left_tree, right_tree, gathered_attributes}
        end

      _ ->
        {left_tree, right_tree, gathered_attributes}
    end
  end

  defp insert_attributes(
         attributes,
         gathered_attributes,
         left_tree,
         right_tree,
         parent_name,
         client_id,
         last_clock
       ) do
    {_negated_attrs, _left_tree, _right_tree, _last_clock} =
      Enum.reduce(attributes, {%{}, left_tree, right_tree, last_clock}, fn {a_k, a_v},
                                                                           {negated_attrs,
                                                                            left_tree, right_tree,
                                                                            last_clock} ->
        current_val = Map.get(gathered_attributes, a_k)

        if current_val == a_v do
          {negated_attrs, left_tree, right_tree, last_clock}
        else
          left_id =
            case FingerTree.last(left_tree) do
              nil -> nil
              %Item{} = item -> Item.last_id(item)
            end

          right_id =
            case FingerTree.first(right_tree) do
              nil -> nil
              %Item{id: id} -> id
            end

          item =
            Item.new(
              id: ID.new(client_id, last_clock),
              content: [Format.new(a_k, a_v)],
              parent_name: parent_name,
              origin: left_id,
              right_origin: right_id
            )

          left_tree = FingerTree.conj(left_tree, item)

          {Map.put(negated_attrs, a_k, current_val), left_tree, right_tree,
           last_clock + Item.content_length(item)}
        end
      end)
  end

  defp do_insert_text(text, left_tree, right_tree, parent_name, client_id, last_clock) do
    left_id =
      case FingerTree.last(left_tree) do
        nil -> nil
        %Item{} = item -> Item.last_id(item)
      end

    right_id =
      case FingerTree.first(right_tree) do
        nil -> nil
        %Item{id: id} -> id
      end

    {_left_tree, _last_clock} =
      text
      |> String.split("", trim: true)
      |> Enum.reduce({left_tree, last_clock}, fn letter, {left_tree, last_clock} ->
        item =
          Item.new(
            id: ID.new(client_id, last_clock),
            content: [letter],
            parent_name: parent_name,
            origin: left_id,
            right_origin: right_id
          )

        {FingerTree.conj(left_tree, item), last_clock + Item.content_length(item)}
      end)
  end

  defp insert_negated_attributes(
         negated_attrs,
         left_tree,
         right_tree,
         parent_name,
         client_id,
         last_clock
       ) do
    case FingerTree.first(right_tree) do
      %Item{deleted?: true} = item ->
        insert_negated_attributes(
          negated_attrs,
          FingerTree.conj(left_tree, item),
          FingerTree.rest(right_tree),
          parent_name,
          client_id,
          last_clock
        )

      %Item{content: [%Format{key: key, value: value}]} = item ->
        if Map.get(negated_attrs, key) == value do
          insert_negated_attributes(
            Map.delete(negated_attrs, key),
            FingerTree.conj(left_tree, item),
            FingerTree.rest(right_tree),
            parent_name,
            client_id,
            last_clock
          )
        else
          do_insert_negated_attributes(
            negated_attrs,
            left_tree,
            right_tree,
            parent_name,
            client_id,
            last_clock
          )
        end

      _ ->
        do_insert_negated_attributes(
          negated_attrs,
          left_tree,
          right_tree,
          parent_name,
          client_id,
          last_clock
        )
    end
  end

  defp do_insert_negated_attributes(
         negated_attrs,
         left_tree,
         right_tree,
         parent_name,
         client_id,
         last_clock
       ) do
    {left_tree, _last_clock} =
      negated_attrs
      |> Enum.reduce({left_tree, last_clock}, fn {k, v}, {left_tree, last_clock} ->
        left_id =
          case FingerTree.last(left_tree) do
            nil -> nil
            %Item{} = item -> Item.last_id(item)
          end

        right_id =
          case FingerTree.first(right_tree) do
            nil -> nil
            %Item{id: id} -> id
          end

        item =
          Item.new(
            id: ID.new(client_id, last_clock),
            content: [Format.new(k, v)],
            parent_name: parent_name,
            origin: left_id,
            right_origin: right_id
          )

        {FingerTree.conj(left_tree, item), last_clock + Item.content_length(item)}
      end)

    {left_tree, right_tree}
  end

  defp do_delete(collected_items, %EmptyTree{} = right_tree, _length, gathered_attributes),
    do: {collected_items, right_tree, gathered_attributes}

  defp do_delete(collected_items, right_tree, length, gathered_attributes) do
    case FingerTree.first(right_tree) do
      %Item{deleted?: true} = item ->
        do_delete(
          [item | collected_items],
          FingerTree.rest(right_tree),
          length,
          gathered_attributes
        )

      %Item{content: [%Format{key: key, value: value}]} = item ->
        do_delete(
          [item | collected_items],
          FingerTree.rest(right_tree),
          length,
          Map.put(gathered_attributes, key, value)
        )

      %Item{} = item ->
        if length == 0 do
          {collected_items, right_tree, gathered_attributes}
        else
          do_delete(
            [Item.delete(item) | collected_items],
            FingerTree.rest(right_tree),
            length - Item.content_length(item),
            gathered_attributes
          )
        end
    end
  end

  defp meter_object do
    FingerTree.MeterObject.new(
      fn
        %Item{id: id} = item ->
          len =
            case item do
              %Item{content: [%Format{}]} -> 0
              _ -> item.length
            end

          %Meter{
            highest_clocks: %{id.client => id.clock},
            highest_clocks_with_length: %{id.client => id.clock + len},
            len: len
          }
      end,
      %Meter{highest_clocks: %{}, highest_clocks_with_length: %{}, len: 0},
      fn %Meter{} = meter1, %Meter{} = meter2 ->
        %Meter{
          highest_clocks:
            Map.merge(meter1.highest_clocks, meter2.highest_clocks, fn _k, c1, c2 ->
              max(c1, c2)
            end),
          highest_clocks_with_length:
            Map.merge(
              meter1.highest_clocks_with_length,
              meter2.highest_clocks_with_length,
              fn _k, c1, c2 ->
                max(c1, c2)
              end
            ),
          len: meter1.len + meter2.len
        }
      end
    )
  end

  defimpl Enumerable do
    def count(%Tree{} = tree) do
      %Meter{len: tree_len} = FingerTree.measure(tree.ft)
      {:ok, tree_len}
    end

    def member?(_seq, _element) do
      {:error, __MODULE__}
    end

    def reduce(seq, acc, fun)

    def reduce(%Tree{} = tree, {:cont, acc}, fun) do
      case FingerTree.first(tree.ft) do
        nil -> {:done, acc}
        element -> reduce(%{tree | ft: FingerTree.rest(tree.ft)}, fun.(element, acc), fun)
      end
    end

    def reduce(_seq, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(seq, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(seq, &1, fun)}
    end

    def slice(_) do
      {:error, __MODULE__}
    end
  end

  defimpl Collectable do
    def into(%Tree{} = tree) do
      collector_fun = fn
        %Tree{ft: acc_ft} = acc, {:cont, value} ->
          %{acc | ft: FingerTree.conj(acc_ft, value)}

        acc, :done ->
          acc

        _acc, :halt ->
          :ok
      end

      initial_acc = tree

      {initial_acc, collector_fun}
    end
  end
end
