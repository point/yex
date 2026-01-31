defmodule Y.Type.Xml.XmlTree do
  @moduledoc """
  FingerTree-based tree for XML children (XmlElement, XmlText).
  Similar to ArrayTree but used for XML fragment/element children.
  """

  alias __MODULE__
  alias Y.Item
  alias Y.ID

  @type t() :: %XmlTree{ft: FingerTree.t()}
  defstruct [:ft]

  defmodule Meter do
    @enforce_keys [:highest_clocks, :highest_clocks_with_length, :len]
    defstruct highest_clocks: %{}, highest_clocks_with_length: %{}, len: 0
  end

  use Y.Type.GeneralTree, mod: XmlTree

  def new do
    %XmlTree{ft: FingerTree.finger_tree(meter_object())}
  end

  def new(meter_object) do
    %XmlTree{ft: FingerTree.finger_tree(meter_object)}
  end

  def put(%XmlTree{ft: %EmptyTree{} = tree} = xml_tree, _index, %Item{} = item) do
    items = Item.explode(item) |> Enum.reverse()

    tree =
      Enum.reduce(items, tree, fn item, tree ->
        FingerTree.cons(tree, item)
      end)

    {:ok, %XmlTree{xml_tree | ft: tree}}
  end

  def put(
        %XmlTree{ft: tree} = xml_tree,
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
              Item.explode(item)
              |> Enum.map(fn i -> %{i | right_origin: right_origin} end)
              |> Enum.reduce(tree, fn item, tree ->
                FingerTree.conj(tree, item)
              end)
            end)
            |> FingerTree.append(r)

          len_l < index and index < len_l + v.length ->
            diff = index - len_l
            {split_l, split_r} = Item.split(v, diff)

            right_origin = Item.id(split_r)
            item = %{item | origin: Item.last_id(split_l), right_origin: right_origin}

            l
            |> FingerTree.conj(split_l)
            |> then(fn tree ->
              Item.explode(item)
              |> Enum.map(fn i -> %{i | right_origin: right_origin} end)
              |> Enum.reduce(tree, fn item, tree ->
                FingerTree.conj(tree, item)
              end)
            end)
            |> FingerTree.conj(split_r)
            |> FingerTree.append(r)
        end
      end

    {:ok, %{xml_tree | ft: new_tree}}
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
    )
  end

  defimpl Collectable do
    def into(%XmlTree{} = tree) do
      collector_fun = fn
        %XmlTree{ft: acc_ft} = acc, {:cont, value} ->
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

    def member?(_xml_tree, _element) do
      {:error, __MODULE__}
    end

    def reduce(xml_tree, acc, fun)

    def reduce(%XmlTree{ft: tree} = xml_tree, {:cont, acc}, fun) do
      case FingerTree.first(tree) do
        nil -> {:done, acc}
        element -> reduce(%{xml_tree | ft: FingerTree.rest(tree)}, fun.(element, acc), fun)
      end
    end

    def reduce(_xml_tree, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(xml_tree, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(xml_tree, &1, fun)}
    end

    def slice(_) do
      {:error, __MODULE__}
    end
  end
end
