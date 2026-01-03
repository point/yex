defmodule Y.Type.Array.ArrayTree do
  alias __MODULE__
  alias Y.Item
  alias Y.ID

  @type t() :: %ArrayTree{ft: FingerTree.t()}
  defstruct [:ft]

  defmodule Meter do
    @enforce_keys [:highest_clocks, :highest_clocks_with_length, :len]
    defstruct highest_clocks: %{}, highest_clocks_with_length: %{}, len: 0
  end

  use Y.Type.GeneralTree, mod: ArrayTree

  def new do
    %ArrayTree{ft: FingerTree.finger_tree(meter_object())}
  end

  def new(meter_object) do
    %ArrayTree{ft: FingerTree.finger_tree(meter_object)}
  end

  def put(%ArrayTree{ft: %EmptyTree{} = tree} = array_tree, _index, %Item{} = item) do
    items = Item.explode(item) |> Enum.reverse()

    tree =
      Enum.reduce(items, tree, fn item, tree ->
        FingerTree.cons(tree, item)
      end)

    {:ok, %ArrayTree{array_tree | ft: tree}}
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
            right_origin = Item.id(next)
            item = %{item | origin: Item.last_id(v), right_origin: right_origin}

            l
            |> FingerTree.conj(v)
            |> then(fn tree ->
              # Explode and preserve right_origin for all items in the sequence
              Item.explode(item)
              |> Enum.map(fn i -> %{i | right_origin: right_origin} end)
              |> Enum.reduce(tree, fn item, tree ->
                FingerTree.conj(tree, item)
              end)
            end)
            # Don't modify existing items' origins - just append them as-is
            |> FingerTree.append(r)

          len_l < index and index < len_l + v.length ->
            diff = index - len_l
            {split_l, split_r} = Item.split(v, diff)

            right_origin = Item.id(split_r)
            item = %{item | origin: Item.last_id(split_l), right_origin: right_origin}

            l
            |> FingerTree.conj(split_l)
            |> then(fn tree ->
              # Explode and preserve right_origin for all items in the sequence
              Item.explode(item)
              |> Enum.map(fn i -> %{i | right_origin: right_origin} end)
              |> Enum.reduce(tree, fn item, tree ->
                FingerTree.conj(tree, item)
              end)
            end)
            # Don't modify split_r's origin - keep it pointing to split_l
            |> FingerTree.conj(split_r)
            |> FingerTree.append(r)
        end
      end

    {:ok, %{array_tree | ft: new_tree}}
  end

  defp meter_object do
    FingerTree.MeterObject.new(
      fn
        %Item{id: id, deleted?: true} = item ->
          len = item.length

          %Meter{
            highest_clocks: %{id.client => id.clock},
            highest_clocks_with_length: %{id.client => id.clock + len},
            len: 0
          }

        %Item{id: id} = item ->
          len = item.length

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
      # ,
      # fn %Item{id: id1}, %Item{id: id2} ->
      #   Kernel.<=({id1.client, id1.clock}, {id2.client, id2.clock})
      # end
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

    def slice(_) do
      {:error, __MODULE__}
    end
  end
end
