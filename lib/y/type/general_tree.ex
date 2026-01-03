defmodule Y.Type.GeneralTree do
  defmacro __using__(opts) do
    mod = Keyword.fetch!(opts, :mod)

    quote do
      alias FingerTree.EmptyTree
      alias Y.Item
      alias Y.ID

      def highest_clock_with_length(%unquote(mod){ft: tree}, nil) do
        %unquote(mod).Meter{highest_clocks_with_length: cl} = FingerTree.measure(tree)

        cl
        |> Map.values()
        |> Enum.max(fn -> 0 end)
      end

      def highest_clock_with_length(%unquote(mod){ft: tree}, client_id) do
        %unquote(mod).Meter{highest_clocks_with_length: cl} = FingerTree.measure(tree)

        case Map.fetch(cl, client_id) do
          {:ok, clock_len} -> clock_len
          _ -> 0
        end
      end

      def highest_clock(%unquote(mod){ft: tree}, nil) do
        %unquote(mod).Meter{highest_clocks: c} = FingerTree.measure(tree)

        c
        |> Map.values()
        |> Enum.max(fn -> 0 end)
      end

      def highest_clock(%unquote(mod){ft: tree}, client_id) do
        %unquote(mod).Meter{highest_clocks: c} = FingerTree.measure(tree)

        case Map.fetch(c, client_id) do
          {:ok, clock} -> clock
          _ -> 0
        end
      end

      def highest_clock_with_length_by_client_id(%unquote(mod){ft: tree}) do
        %unquote(mod).Meter{highest_clocks_with_length: cl} = FingerTree.measure(tree)
        cl
      end

      def highest_clock_by_client_id(%unquote(mod){ft: tree}) do
        %unquote(mod).Meter{highest_clocks: c} = FingerTree.measure(tree)
        c
      end

      def cons!(%unquote(mod){ft: tree} = array_tree, value),
        do: %{array_tree | ft: FingerTree.cons(tree, value)}

      def conj!(%unquote(mod){ft: tree} = array_tree, value),
        do: %{array_tree | ft: FingerTree.conj(tree, value)}

      @spec empty?(t()) :: boolean()
      def empty?(%unquote(mod){ft: tree}), do: FingerTree.empty?(tree)

      def to_list(%unquote(mod){ft: tree}), do: FingerTree.to_list(tree)

      def find(tree, id, default \\ nil)

      def find(%unquote(mod){ft: %EmptyTree{}}, _id, default), do: default

      def find(%unquote(mod){ft: tree} = array_tree, id, default) do
        {l, v, _} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, id.client) do
              {:ok, c} -> c >= id.clock
              _ -> false
            end
          end)

        prev = FingerTree.last(l)

        cond do
          # Check if v matches both client AND clock
          v != nil && v.id.client == id.client && v.id.clock == id.clock ->
            v

          # Check if id is within v's range (same client)
          v != nil && v.id.client == id.client &&
            id.clock > v.id.clock && id.clock <= v.id.clock + Item.content_length(v) - 1 ->
            v

          # Check prev (same client)
          prev != nil && prev.id.client == id.client &&
            id.clock >= prev.id.clock &&
              id.clock <= prev.id.clock + Item.content_length(prev) - 1 ->
            prev

          :otherwise ->
            # Fall back to linear search if the measure-based approach didn't work
            # This handles cases where items are not in clock order within the tree
            do_find_linear(array_tree, id, default)
        end
      end

      # Linear search through the tree to find an item by ID
      # Uses first/rest to short-circuit as soon as the item is found
      defp do_find_linear(%unquote(mod){ft: %EmptyTree{}}, _id, default), do: default

      defp do_find_linear(%unquote(mod){ft: tree} = array_tree, id, default) do
        item = FingerTree.first(tree)

        if item.id.client == id.client &&
             id.clock >= item.id.clock &&
             id.clock <= item.id.clock + Item.content_length(item) - 1 do
          item
        else
          do_find_linear(%{array_tree | ft: FingerTree.rest(tree)}, id, default)
        end
      end

      def replace(%unquote(mod){ft: tree} = array_tree, item, with_items)
          when is_list(with_items) do
        {l, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, item.id.client) do
              {:ok, c} -> c >= item.id.clock
              _ -> false
            end
          end)

        if v == item do
          tree =
            with_items
            |> Enum.flat_map(&Item.explode/1)
            |> Enum.reduce(l, fn item, tree -> FingerTree.conj(tree, item) end)
            |> FingerTree.append(r)

          {:ok, %{array_tree | ft: tree}}
        else
          {:error, "Item not found"}
        end
      end

      def transform(
            %unquote(mod){ft: tree} = array_tree,
            %Item{} = starting_item,
            acc \\ nil,
            fun
          )
          when is_function(fun, 2) do
        {l, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, starting_item.id.client) do
              {:ok, c} -> c >= starting_item.id.clock
              _ -> false
            end
          end)

        if v == starting_item do
          tree =
            case do_transform(v, l, r, acc, fun) do
              {left_tree, nil} ->
                left_tree

              {left_tree, right_tree} ->
                FingerTree.append(left_tree, right_tree)
            end

          {:ok, %{array_tree | ft: tree}}
        else
          # Fallback to linear search when measure-based split doesn't find the item
          do_transform_linear(array_tree, starting_item, acc, fun)
        end
      end

      # Linear search fallback for transform when items aren't in clock order
      defp do_transform_linear(
             %unquote(mod){ft: tree} = array_tree,
             %Item{} = starting_item,
             acc,
             fun
           ) do
        empty_tree = FingerTree.finger_tree(tree.meter_object)

        case find_item_linear(tree, starting_item, empty_tree) do
          {:found, l, v, r} ->
            new_tree =
              case do_transform(v, l, r, acc, fun) do
                {left_tree, nil} -> left_tree
                {left_tree, right_tree} -> FingerTree.append(left_tree, right_tree)
              end

            {:ok, %{array_tree | ft: new_tree}}

          :not_found ->
            {:error, "Item not found"}
        end
      end

      defp find_item_linear(%EmptyTree{}, _target, _left_acc), do: :not_found

      defp find_item_linear(tree, target, left_acc) do
        item = FingerTree.first(tree)
        rest = FingerTree.rest(tree)

        if item == target do
          {:found, left_acc, item, rest}
        else
          find_item_linear(rest, target, FingerTree.conj(left_acc, item))
        end
      end

      defp do_transform(nil, left_tree, right_tree, _acc, _fun), do: {left_tree, right_tree}

      defp do_transform(_, left_tree, nil, _acc, _fun),
        do: {left_tree, nil}

      defp do_transform(%Item{} = item, left_tree, right_tree, acc, fun) do
        case fun.(item, acc) do
          {%Item{} = new_item, new_acc} ->
            do_transform(
              FingerTree.first(right_tree),
              FingerTree.conj(left_tree, new_item),
              FingerTree.rest(right_tree),
              new_acc,
              fun
            )

          %Item{} = new_item ->
            do_transform(
              FingerTree.first(right_tree),
              FingerTree.conj(left_tree, new_item),
              FingerTree.rest(right_tree),
              acc,
              fun
            )

          nil ->
            {FingerTree.conj(left_tree, item), right_tree}
        end
      end

      def between(%unquote(mod){ft: tree}, %ID{} = left, %ID{} = right) do
        {_, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, left.client) do
              {:ok, c} -> c >= left.clock
              _ -> false
            end
          end)

        if v.id == left do
          do_between(r, right, [v]) |> Enum.reverse()
        else
          []
        end
      end

      defp do_between(%EmptyTree{}, _, acc), do: acc

      defp do_between(tree, right, acc) do
        f = FingerTree.first(tree)

        # Stop BEFORE reaching the right boundary (like Y.js: while o !== this.right)
        if f.id == right do
          acc
        else
          do_between(FingerTree.rest(tree), right, [f | acc])
        end
      end

      def add_after(%unquote(mod){ft: tree} = at, %Item{} = after_item, %Item{} = item) do
        {l, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, after_item.id.client) do
              {:ok, c} -> c >= after_item.id.clock
              _ -> false
            end
          end)

        if v == after_item do
          {:ok,
           %{
             at
             | ft:
                 l
                 |> FingerTree.conj(v)
                 |> then(fn tree ->
                   Enum.reduce(Item.explode(item), tree, fn item, tree ->
                     FingerTree.conj(tree, item)
                   end)
                 end)
                 |> FingerTree.append(r)
           }}
        else
          # Fallback to linear search
          do_add_after_linear(at, after_item, item)
        end
      end

      defp do_add_after_linear(%unquote(mod){ft: tree} = at, %Item{} = after_item, %Item{} = item) do
        empty_tree = FingerTree.finger_tree(tree.meter_object)

        case find_item_linear(tree, after_item, empty_tree) do
          {:found, l, v, r} ->
            {:ok,
             %{
               at
               | ft:
                   l
                   |> FingerTree.conj(v)
                   |> then(fn tree ->
                     Enum.reduce(Item.explode(item), tree, fn item, tree ->
                       FingerTree.conj(tree, item)
                     end)
                   end)
                   |> FingerTree.append(r)
             }}

          :not_found ->
            {:error, "Item not found"}
        end
      end

      def add_before(%unquote(mod){ft: %EmptyTree{} = ft} = at, _, %Item{} = item),
        do:
          {:ok,
           %{
             at
             | ft:
                 Enum.reduce(Item.explode(item), ft, fn item, ft -> FingerTree.conj(ft, item) end)
           }}

      def add_before(%unquote(mod){ft: tree} = at, %Item{} = before_item, %Item{} = item) do
        {l, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, before_item.id.client) do
              {:ok, c} -> c >= before_item.id.clock
              _ -> false
            end
          end)

        if v == before_item do
          {:ok,
           %{
             at
             | ft:
                 l
                 |> then(fn tree ->
                   Enum.reduce(Item.explode(item), tree, fn item, tree ->
                     FingerTree.conj(tree, item)
                   end)
                 end)
                 |> FingerTree.conj(v)
                 |> FingerTree.append(r)
           }}
        else
          # Fallback to linear search
          do_add_before_linear(at, before_item, item)
        end
      end

      defp do_add_before_linear(
             %unquote(mod){ft: tree} = at,
             %Item{} = before_item,
             %Item{} = item
           ) do
        empty_tree = FingerTree.finger_tree(tree.meter_object)

        case find_item_linear(tree, before_item, empty_tree) do
          {:found, l, v, r} ->
            {:ok,
             %{
               at
               | ft:
                   l
                   |> then(fn tree ->
                     Enum.reduce(Item.explode(item), tree, fn item, tree ->
                       FingerTree.conj(tree, item)
                     end)
                   end)
                   |> FingerTree.conj(v)
                   |> FingerTree.append(r)
             }}

          :not_found ->
            {:error, "Item not found"}
        end
      end

      def next(%unquote(mod){ft: tree} = array_tree, %Item{} = item) do
        {_, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, item.id.client) do
              {:ok, c} -> c >= item.id.clock
              _ -> false
            end
          end)

        if v.id == item.id do
          FingerTree.first(r)
        else
          # Fall back to linear search
          do_find_next_linear(array_tree, item)
        end
      end

      defp do_find_next_linear(%unquote(mod){ft: %EmptyTree{}}, _item), do: nil

      defp do_find_next_linear(%unquote(mod){ft: tree} = array_tree, item) do
        current = FingerTree.first(tree)
        rest_tree = %{array_tree | ft: FingerTree.rest(tree)}

        if current.id == item.id do
          FingerTree.first(FingerTree.rest(tree))
        else
          do_find_next_linear(rest_tree, item)
        end
      end

      def prev(%unquote(mod){ft: tree} = array_tree, %Item{} = item) do
        {l, v, _} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, item.id.client) do
              {:ok, c} -> c >= item.id.clock
              _ -> false
            end
          end)

        if v.id == item.id do
          FingerTree.last(l)
        else
          # Fall back to linear search
          do_find_prev_linear(array_tree, item, nil)
        end
      end

      defp do_find_prev_linear(%unquote(mod){ft: %EmptyTree{}}, _item, prev_item), do: prev_item

      defp do_find_prev_linear(%unquote(mod){ft: tree} = array_tree, item, prev_item) do
        current = FingerTree.first(tree)
        rest_tree = %{array_tree | ft: FingerTree.rest(tree)}

        if current.id == item.id do
          prev_item
        else
          do_find_prev_linear(rest_tree, item, current)
        end
      end

      def first(%unquote(mod){ft: tree}), do: FingerTree.first(tree)
      def last(%unquote(mod){ft: tree}), do: FingerTree.last(tree)

      def rest(%unquote(mod){ft: tree} = array_tree),
        do: %{array_tree | ft: FingerTree.rest(tree)}

      def butlast(%unquote(mod){ft: tree} = array_tree),
        do: %{array_tree | ft: FingerTree.butlast(tree)}

      def length(%unquote(mod){ft: tree}) do
        %unquote(mod).Meter{len: len} = FingerTree.measure(tree)
        len
      end

      def at(%unquote(mod){ft: %EmptyTree{}}, _index), do: nil

      def at(%unquote(mod){ft: tree} = array_tree, index) do
        if index > unquote(mod).length(array_tree) - 1 do
          nil
        else
          {_, v, _} =
            FingerTree.split(tree, fn %{len: len} ->
              len > index
            end)

          v
        end
      end

      defoverridable(
        highest_clock_with_length: 2,
        highest_clock: 2,
        highest_clock_with_length_by_client_id: 1,
        highest_clock_by_client_id: 1,
        cons!: 2,
        conj!: 2,
        empty?: 1,
        to_list: 1,
        find: 3,
        replace: 3,
        transform: 4,
        between: 3,
        add_after: 3,
        add_before: 3,
        next: 2,
        prev: 2,
        first: 1,
        last: 1,
        rest: 1,
        length: 1,
        at: 2
      )
    end
  end
end
