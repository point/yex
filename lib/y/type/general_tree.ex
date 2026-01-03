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

      def find(%unquote(mod){ft: tree}, id, default) do
        {l, v, _} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, id.client) do
              {:ok, c} -> c >= id.clock
              _ -> false
            end
          end)

        prev = FingerTree.last(l)

        cond do
          v.id.clock == id.clock ->
            v

          id.clock > v.id.clock && id.clock <= v.id.clock + Item.content_length(v) ->
            v

          prev && id.clock > prev.id.clock &&
              id.clock <= prev.id.clock + Item.content_length(prev) ->
            prev

          :otherwise ->
            default
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
          {:error, "Item not found"}
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

        if f.id == right do
          [f | acc]
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
          {:error, "Item not found"}
        end
      end

      def next(%unquote(mod){ft: tree}, %Item{} = item) do
        {_, v, r} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, item.id.client) do
              {:ok, c} -> c >= item.id.clock
              _ -> false
            end
          end)

        if v == item, do: FingerTree.first(r)
      end

      def prev(%unquote(mod){ft: tree}, %Item{} = item) do
        {l, v, _} =
          FingerTree.split(tree, fn %{highest_clocks: clocks} ->
            case Map.fetch(clocks, item.id.client) do
              {:ok, c} -> c >= item.id.clock
              _ -> false
            end
          end)

        if v == item, do: FingerTree.last(l)
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
