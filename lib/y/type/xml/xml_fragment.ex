defmodule Y.Type.XmlFragment do
  @moduledoc """
  XML Fragment type - a container for XML children without element metadata.
  Similar to YXmlFragment in Y.js.

  XmlFragment can contain XmlElement and XmlText children.
  """

  alias __MODULE__
  alias Y.Type.Xml.XmlTree
  alias Y.Type.Unknown
  alias Y.Type
  alias Y.Content.Deleted
  alias Y.Transaction
  alias Y.Doc
  alias Y.Item
  alias Y.ID

  require Logger

  defstruct tree: nil,
            doc_name: nil,
            name: nil

  @doc """
  Create a new XmlFragment.
  """
  def new(%Doc{name: doc_name}, name \\ UUID.uuid4()) do
    %XmlFragment{doc_name: doc_name, name: name, tree: XmlTree.new()}
  end

  @doc """
  Insert children at the given index.
  Children should be XmlElement or XmlText types.
  """
  def insert(fragment, transaction, index, children)

  def insert({:ok, %XmlFragment{} = fragment, %Transaction{} = transaction}, index, children),
    do: insert(fragment, transaction, index, children)

  def insert(%XmlFragment{} = fragment, %Transaction{} = transaction, index, children)
      when is_list(children) do
    Enum.reduce_while(children, {:ok, fragment, transaction}, fn child, {:ok, frag, trans} ->
      case do_insert(frag, trans, index, child) do
        {:ok, new_frag, new_trans} ->
          {:cont, {:ok, new_frag, new_trans}}

        err ->
          {:halt, err}
      end
    end)
  end

  def insert(%XmlFragment{} = fragment, %Transaction{} = transaction, index, child) do
    do_insert(fragment, transaction, index, child)
  end

  defp do_insert(
         %XmlFragment{tree: tree, name: parent_name} = fragment,
         %Transaction{doc: doc} = transaction,
         index,
         child
       ) do
    clock_length = Doc.highest_clock_with_length(transaction, doc.client_id)

    item =
      Item.new(
        id: ID.new(doc.client_id, clock_length),
        content: [child],
        parent_name: parent_name
      )

    with {:ok, new_tree} <- XmlTree.put(tree, index, item),
         new_fragment = %{fragment | tree: new_tree},
         {:ok, new_transaction} <- Transaction.update(transaction, new_fragment) do
      {:ok, new_fragment, new_transaction}
    end
  end

  @doc """
  Delete children starting at index.
  """
  def delete(fragment, transaction, index, length \\ 1)

  def delete(%XmlFragment{} = _fragment, %Transaction{} = transaction, _index, 0),
    do: {:ok, transaction}

  def delete(%XmlFragment{tree: tree} = fragment, %Transaction{} = transaction, index, length) do
    case XmlTree.at(tree, index) do
      nil ->
        Logger.warning("Fail to find item to delete at position",
          fragment: fragment,
          index: index
        )

        {:ok, fragment, transaction}

      %Item{} = starting_item ->
        do_delete(fragment, transaction, starting_item, length)
    end
  end

  defp do_delete(%XmlFragment{} = fragment, transaction, starting_item, length) do
    with {:ok, new_tree} <-
           XmlTree.transform(fragment.tree, starting_item, 0, fn item, pos ->
             if pos < length, do: {Item.delete(item), pos + 1}
           end),
         {:ok, transaction} <-
           Transaction.update(transaction, %{fragment | tree: new_tree}) do
      {:ok, %{fragment | tree: new_tree}, transaction}
    else
      {:error, msg} ->
        Logger.warning("Fail to delete item(s): #{msg}",
          fragment: fragment,
          starting_item: starting_item,
          length: length
        )

        {:error, fragment, transaction}
    end
  end

  @doc """
  Get child at index.
  """
  def get(%XmlFragment{tree: tree}, index) do
    case XmlTree.at(tree, index) do
      %Item{deleted?: false, content: [content]} -> content
      _ -> nil
    end
  end

  @doc """
  Get length of children (non-deleted).
  """
  def length(%XmlFragment{tree: tree}), do: XmlTree.length(tree)

  @doc """
  Convert to string representation.
  Concatenates toString of all children.
  """
  def to_string(%XmlFragment{} = fragment) do
    fragment
    |> Type.to_list()
    |> Enum.map(&child_to_string/1)
    |> Enum.join("")
  end

  defp child_to_string(%Y.Type.XmlElement{} = elem), do: Y.Type.XmlElement.to_string(elem)
  defp child_to_string(%Y.Type.XmlText{} = text), do: Y.Type.XmlText.to_string(text)
  defp child_to_string(str) when is_binary(str), do: str
  defp child_to_string(other), do: inspect(other)

  @doc """
  Convert from Unknown type (used during decoding).
  """
  def from_unknown(%Unknown{} = u) do
    tree =
      u
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.reduce(XmlTree.new(), fn item, tree ->
        XmlTree.conj!(tree, item)
      end)

    %XmlFragment{doc_name: u.doc_name, name: u.name, tree: tree}
  end

  defdelegate to_list(fragment), to: Type
  defdelegate to_list(fragment, opts), to: Type
  defdelegate find(fragment, id, default \\ nil), to: Type
  defdelegate between(fragment, left, right), to: Type

  # Y.Type protocol implementation
  defimpl Type do
    def highest_clock(%XmlFragment{tree: tree}, client),
      do: XmlTree.highest_clock(tree, client)

    def highest_clock_with_length(%XmlFragment{tree: tree}, client),
      do: XmlTree.highest_clock_with_length(tree, client)

    def highest_clock_by_client_id(%XmlFragment{tree: tree}),
      do: XmlTree.highest_clock_by_client_id(tree)

    def highest_clock_with_length_by_client_id(%XmlFragment{tree: tree}),
      do: XmlTree.highest_clock_with_length_by_client_id(tree)

    def pack(%XmlFragment{tree: tree} = fragment) do
      new_tree =
        tree
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
        |> Enum.into(XmlTree.new())

      %{fragment | tree: new_tree}
    end

    def to_list(%XmlFragment{tree: tree}, opts \\ []) do
      as_items = Keyword.get(opts, :as_items, false)
      with_deleted = Keyword.get(opts, :with_deleted, false)

      items =
        if with_deleted do
          XmlTree.to_list(tree)
        else
          XmlTree.to_list(tree) |> Enum.reject(& &1.deleted?)
        end

      if as_items, do: items, else: items |> Enum.map(& &1.content) |> List.flatten()
    end

    def find(%XmlFragment{tree: tree}, %ID{} = id, default),
      do: tree |> XmlTree.find(id, default)

    def unsafe_replace(
          %XmlFragment{tree: tree} = fragment,
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
          case XmlTree.replace(tree, item, with_items) do
            {:ok, new_tree} -> {:ok, %{fragment | tree: new_tree}}
            err -> err
          end
      end
    end

    def between(%XmlFragment{tree: tree}, %ID{} = left, %ID{} = right) do
      XmlTree.between(tree, left, right)
    end

    def add_after(%XmlFragment{tree: tree} = fragment, %Item{} = after_item, %Item{} = item) do
      case XmlTree.add_after(tree, after_item, item) do
        {:ok, new_tree} -> {:ok, %{fragment | tree: new_tree}}
        err -> err
      end
    end

    def add_before(%XmlFragment{tree: tree} = fragment, nil, %Item{} = item) do
      case XmlTree.put(tree, 0, item) do
        {:ok, tree} -> {:ok, %{fragment | tree: tree}}
        err -> err
      end
    end

    def add_before(%XmlFragment{tree: tree} = fragment, %Item{} = before_item, %Item{} = item) do
      case XmlTree.add_before(tree, before_item, item) do
        {:ok, tree} -> {:ok, %{fragment | tree: tree}}
        err -> err
      end
    end

    def next(%XmlFragment{tree: tree}, %Item{} = item) do
      XmlTree.next(tree, item)
    end

    def prev(%XmlFragment{tree: tree}, %Item{} = item) do
      XmlTree.prev(tree, item)
    end

    def first(%XmlFragment{tree: tree}, _) do
      XmlTree.first(tree)
    end

    def last(%XmlFragment{tree: tree}, _) do
      XmlTree.last(tree)
    end

    def delete(%XmlFragment{tree: tree} = fragment, %Transaction{} = transaction, %ID{} = id) do
      case XmlTree.find(tree, id) do
        nil ->
          Logger.warning("Fail to find item to delete", fragment: fragment, id: id)
          {:ok, transaction}

        %Item{} = starting_item ->
          with {:ok, new_tree} <-
                 XmlTree.transform(tree, starting_item, 0, fn item, pos ->
                   if pos < 1, do: {Item.delete(item), pos + 1}
                 end),
               {:ok, transaction} <-
                 Transaction.update(transaction, %{fragment | tree: new_tree}) do
            {:ok, %{fragment | tree: new_tree}, transaction}
          end
      end
    end

    def type_ref(_), do: 4

    def gc(%XmlFragment{tree: tree} = fragment) do
      new_tree =
        fragment
        |> to_list(as_items: true, with_deleted: true)
        |> Enum.filter(fn
          %Item{content: [%Deleted{}]} -> false
          %Item{deleted?: false} -> false
          _ -> true
        end)
        |> case do
          [] ->
            tree

          items ->
            items
            |> Enum.reduce(tree, fn deleted_item, tree ->
              with %Item{} = item <- XmlTree.find(tree, deleted_item.id),
                   {:ok, new_tree} <-
                     XmlTree.replace(tree, item, [%{item | content: [Deleted.from_item(item)]}]) do
                new_tree
              else
                _ -> tree
              end
            end)
        end

      %{fragment | tree: new_tree}
    end
  end
end
