defmodule Y.Type.Array.ArrayTree do
  alias __MODULE__
  alias FingerTree.EmptyTree
  # alias FingerTree.Protocols.Conjable
  alias Y.Item
  alias Y.ID

  defstruct [:ft]
  @type t() :: %ArrayTree{ft: FingerTree.t()}

  defmodule Meter do
    @enforce_keys [:highest_clocks, :highest_clocks_with_length, :len]
    defstruct highest_clocks: %{}, highest_clocks_with_length: %{}, len: 0
  end

  def new do
    %ArrayTree{ft: FingerTree.finger_tree(meter_object())}
  end

  def highest_clock_with_length(%ArrayTree{ft: tree}, :all) do
    %Meter{highest_clocks_with_length: cl} = FingerTree.measure(tree)
    cl
  end

  def highest_clock_with_length(%ArrayTree{ft: tree}, client_id) do
    %Meter{highest_clocks_with_length: cl} = FingerTree.measure(tree)

    case Map.fetch(cl, client_id) do
      {:ok, clock_len} -> clock_len
      _ -> 0
    end
  end

  def highest_clock(%ArrayTree{ft: tree}, :all) do
    %Meter{highest_clocks: c} = FingerTree.measure(tree)
    c
  end

  def highest_clock(%ArrayTree{ft: tree}, client_id) do
    %Meter{highest_clocks: c} = FingerTree.measure(tree)

    case Map.fetch(c, client_id) do
      {:ok, clock} -> clock
      _ -> 0
    end
  end

  def put(%ArrayTree{ft: %EmptyTree{} = tree} = array_tree, _index, %Item{} = item) do
    {:ok, %ArrayTree{array_tree | ft: FingerTree.cons(tree, item)}}
  end

  def put(
        %ArrayTree{ft: tree} = array_tree,
        index,
        %Item{origin: nil, right_origin: nil} = item
      ) do
    %Meter{len: tree_len} = FingerTree.measure(tree)

    new_tree =
      if index <= 0 || index >= tree_len do
        cond do
          index <= 0 ->
            f = FingerTree.first(tree)
            items = Item.explode(%{item | right_origin: Item.id(f)}) |> Enum.reverse()

            Enum.reduce(items, tree, fn item, tree ->
              FingerTree.cons(tree, item)
            end)

          index >= tree_len ->
            l = FingerTree.last(tree)
            items = Item.explode(%{item | origin: Item.last_id(l)})

            Enum.reduce(items, tree, fn item, tree ->
              FingerTree.conj(tree, item)
            end)
        end
      else
        {l, v, r} =
          FingerTree.split(tree, fn %{len: len} ->
            index <= len
          end)

        %Meter{len: len_l} = FingerTree.measure(l)

        cond do
          len_l + v.length == index ->
            next = FingerTree.first(r)
            item = %{item | origin: Item.last_id(v), right_origin: Item.id(next)}

            l
            |> FingerTree.conj(v)
            |> then(fn tree ->
              Enum.reduce(Item.explode(item), tree, fn item, tree ->
                FingerTree.conj(tree, item)
              end)
            end)
            |> then(fn tree ->
              if next do
                tree
                |> FingerTree.conj(%{next | origin: Item.last_id(item)})
                |> FingerTree.append(FingerTree.rest(r))
              else
                tree |> FingerTree.append(r)
              end
            end)

          len_l < index and index < len_l + v.length ->
            diff = index - len_l
            {split_l, split_r} = Item.split(v, diff)

            item = %{item | origin: Item.last_id(split_l), right_origin: Item.id(split_r)}

            l
            |> FingerTree.conj(split_l)
            |> then(fn tree ->
              Enum.reduce(Item.explode(item), tree, fn item, tree ->
                FingerTree.conj(tree, item)
              end)
            end)
            |> FingerTree.conj(%{split_r | origin: Item.last_id(item)})
            |> FingerTree.append(r)
        end
      end

    {:ok, %{array_tree | ft: new_tree}}
  end

  def cons!(%ArrayTree{ft: tree} = array_tree, value),
    do: %{array_tree | ft: FingerTree.cons(tree, value)}

  def conj!(%ArrayTree{ft: tree} = array_tree, value),
    do: %{array_tree | ft: FingerTree.conj(tree, value)}

  @spec empty?(t()) :: boolean()
  def empty?(%ArrayTree{ft: tree}), do: FingerTree.empty?(tree)

  def to_list(%ArrayTree{ft: tree}), do: FingerTree.to_list(tree)

  def find(%ArrayTree{ft: tree}, id, default \\ nil) do
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

      prev && id.clock > prev.id.clock && id.clock <= prev.id.clock + Item.content_length(prev) ->
        prev

      :otherwise ->
        default
    end
  end

  def replace(%ArrayTree{ft: tree} = array_tree, item, with_items) when is_list(with_items) do
    {l, v, r} =
      FingerTree.split(tree, fn %{highest_clocks: clocks} ->
        Map.fetch!(clocks, item.id.client) >= item.id.clock
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

  def transform(%ArrayTree{ft: tree} = array_tree, %Item{} = starting_item, acc \\ nil, fun)
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

  def do_transform(nil, left_tree, right_tree, _acc, _fun), do: {left_tree, right_tree}

  def do_transform(_, left_tree, nil, _acc, _fun),
    do: {left_tree, nil}

  def do_transform(%Item{} = item, left_tree, right_tree, acc, fun) do
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

  def between(%ArrayTree{ft: tree}, %ID{} = left, %ID{} = right) do
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

  def add_after(%ArrayTree{ft: tree} = at, %Item{} = after_item, %Item{} = item) do
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

  def add_before(%ArrayTree{ft: %EmptyTree{} = ft} = at, _, %Item{} = item),
    do:
      {:ok,
       %{
         at
         | ft: Enum.reduce(Item.explode(item), ft, fn item, ft -> FingerTree.conj(ft, item) end)
       }}

  def add_before(%ArrayTree{ft: tree} = at, %Item{} = before_item, %Item{} = item) do
    {l, v, r} =
      FingerTree.split(tree, fn %{highest_clocks: clocks} ->
        Map.fetch!(clocks, before_item.id.client) >= before_item.id.clock
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

  def next(%ArrayTree{ft: tree}, %Item{} = item) do
    {_, v, r} =
      FingerTree.split(tree, fn %{highest_clocks: clocks} ->
        case Map.fetch(clocks, item.id.client) do
          {:ok, c} -> c >= item.id.clock
          _ -> false
        end
      end)

    if v == item, do: FingerTree.first(r)
  end

  def prev(%ArrayTree{ft: tree}, %Item{} = item) do
    {l, v, _} =
      FingerTree.split(tree, fn %{highest_clocks: clocks} ->
        Map.fetch!(clocks, item.id.client) >= item.id.clock
      end)

    if v == item, do: FingerTree.last(l)
  end

  def first(%ArrayTree{ft: tree}), do: FingerTree.first(tree)
  def last(%ArrayTree{ft: tree}), do: FingerTree.last(tree)

  def length(%ArrayTree{ft: tree}) do
    %Meter{len: len} = FingerTree.measure(tree)
    len
  end

  def at(%ArrayTree{ft: %EmptyTree{}}, _index), do: nil

  def at(%ArrayTree{ft: tree} = array_tree, index) do
    if index > ArrayTree.length(array_tree) - 1 do
      nil
    else
      {_, v, _} =
        FingerTree.split(tree, fn %{len: len} ->
          len > index
        end)

      v
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

  defp meter_object do
    FingerTree.MeterObject.new(
      fn %Item{id: id} = item ->
        len = Item.content_length(item)

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

  defimpl Collectable do
    def into(%ArrayTree{} = tree) do
      collector_fun = fn
        %ArrayTree{ft: acc_ft} = acc, {:cont, value} ->
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

  defimpl Enumerable do
    def count(_) do
      {:error, __MODULE__}
    end

    def member?(_array, _element) do
      {:error, __MODULE__}
    end

    def reduce(array, acc, fun)

    def reduce(%ArrayTree{ft: tree} = array, {:cont, acc}, fun) do
      case FingerTree.first(tree) do
        nil -> {:done, acc}
        element -> reduce(%{array | ft: FingerTree.rest(tree)}, fun.(element, acc), fun)
      end
    end

    def reduce(_array, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(array, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(array, &1, fun)}
    end

    def slice(_array) do
      {:error, __MODULE__}
    end
  end
end
