defmodule Y.Type.XmlElement do
  @moduledoc """
  XML Element type - represents an XML element with tag name, attributes, and children.
  Similar to YXmlElement in Y.js.

  XmlElement extends XmlFragment with:
  - node_name: The tag name (e.g., "div", "p", "span")
  - attributes: Key-value pairs stored as Items (like Map)
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
            attributes: %{},
            node_name: nil,
            doc_name: nil,
            name: nil

  @doc """
  Create a new XmlElement with the given tag name.
  """
  def new(%Doc{name: doc_name}, node_name, name \\ UUID.uuid4()) do
    %XmlElement{
      doc_name: doc_name,
      name: name,
      node_name: node_name,
      tree: XmlTree.new(),
      attributes: %{}
    }
  end

  @doc """
  Insert children at the given index.
  Children should be XmlElement or XmlText types.
  """
  def insert(element, transaction, index, children)

  def insert({:ok, %XmlElement{} = element, %Transaction{} = transaction}, index, children),
    do: insert(element, transaction, index, children)

  def insert(%XmlElement{} = element, %Transaction{} = transaction, index, children)
      when is_list(children) do
    Enum.reduce_while(children, {:ok, element, transaction}, fn child, {:ok, elem, trans} ->
      case do_insert(elem, trans, index, child) do
        {:ok, new_elem, new_trans} ->
          {:cont, {:ok, new_elem, new_trans}}

        err ->
          {:halt, err}
      end
    end)
  end

  def insert(%XmlElement{} = element, %Transaction{} = transaction, index, child) do
    do_insert(element, transaction, index, child)
  end

  defp do_insert(
         %XmlElement{tree: tree, name: parent_name} = element,
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
         new_element = %{element | tree: new_tree},
         {:ok, new_transaction} <- Transaction.update(transaction, new_element) do
      {:ok, new_element, new_transaction}
    end
  end

  @doc """
  Delete children starting at index.
  """
  def delete(element, transaction, index, length \\ 1)

  def delete(%XmlElement{} = _element, %Transaction{} = transaction, _index, 0),
    do: {:ok, transaction}

  def delete(%XmlElement{tree: tree} = element, %Transaction{} = transaction, index, length) do
    case XmlTree.at(tree, index) do
      nil ->
        Logger.warning("Fail to find item to delete at position",
          element: element,
          index: index
        )

        {:ok, element, transaction}

      %Item{} = starting_item ->
        do_delete(element, transaction, starting_item, length)
    end
  end

  defp do_delete(%XmlElement{} = element, transaction, starting_item, length) do
    with {:ok, new_tree} <-
           XmlTree.transform(element.tree, starting_item, 0, fn item, pos ->
             if pos < length, do: {Item.delete(item), pos + 1}
           end),
         {:ok, transaction} <-
           Transaction.update(transaction, %{element | tree: new_tree}) do
      {:ok, %{element | tree: new_tree}, transaction}
    else
      {:error, msg} ->
        Logger.warning("Fail to delete item(s): #{msg}",
          element: element,
          starting_item: starting_item,
          length: length
        )

        {:error, element, transaction}
    end
  end

  @doc """
  Get child at index.
  """
  def get(%XmlElement{tree: tree}, index) do
    case XmlTree.at(tree, index) do
      %Item{deleted?: false, content: [content]} -> content
      _ -> nil
    end
  end

  @doc """
  Get length of children (non-deleted).
  """
  def length(%XmlElement{tree: tree}), do: XmlTree.length(tree)

  @doc """
  Set an attribute on the element.
  Attributes are stored similarly to Map items with parent_sub.
  """
  def set_attribute(element, transaction, attr_name, value)

  def set_attribute(
        {:ok, %XmlElement{} = element, %Transaction{} = transaction},
        attr_name,
        value
      ),
      do: set_attribute(element, transaction, attr_name, value)

  def set_attribute(
        %XmlElement{attributes: attrs, name: parent_name} = element,
        %Transaction{doc: doc} = transaction,
        attr_name,
        value
      ) do
    clock_length = Doc.highest_clock_with_length(transaction, doc.client_id)

    item =
      Item.new(
        id: ID.new(doc.client_id, clock_length),
        content: [value],
        parent_name: parent_name,
        parent_sub: attr_name
      )

    new_attrs =
      Map.update(attrs, attr_name, [item], fn [active_item | rest] ->
        item = %{item | origin: active_item.id}
        old_active = Item.delete(active_item)
        [item | [old_active | rest]]
      end)

    new_element = %{element | attributes: new_attrs}

    case Transaction.update(transaction, new_element) do
      {:ok, transaction} -> {:ok, new_element, transaction}
      err -> err
    end
  end

  @doc """
  Get an attribute value.
  """
  def get_attribute(%XmlElement{attributes: attrs}, attr_name, default \\ nil) do
    case Map.fetch(attrs, attr_name) do
      {:ok, [%Item{deleted?: false, content: [content]} | _]} -> content
      _ -> default
    end
  end

  @doc """
  Remove an attribute from the element.
  """
  def remove_attribute(%XmlElement{attributes: attrs} = element, transaction, attr_name) do
    case Map.fetch(attrs, attr_name) do
      {:ok, [%Item{deleted?: false} = item | rest]} ->
        deleted_item = Item.delete(item)

        new_attrs =
          Map.put(attrs, attr_name, [deleted_item | rest])

        new_element = %{element | attributes: new_attrs}

        case Transaction.update(transaction, new_element) do
          {:ok, transaction} -> {:ok, new_element, transaction}
          err -> err
        end

      _ ->
        {:ok, element, transaction}
    end
  end

  @doc """
  Check if an attribute exists.
  """
  def has_attribute?(%XmlElement{attributes: attrs}, attr_name) do
    case Map.fetch(attrs, attr_name) do
      {:ok, [%Item{deleted?: false} | _]} -> true
      _ -> false
    end
  end

  @doc """
  Get all attributes as a map.
  """
  def get_attributes(%XmlElement{attributes: attrs}) do
    attrs
    |> Enum.reduce(%{}, fn {key, items}, acc ->
      case items do
        [%Item{deleted?: false, content: [content]} | _] ->
          Map.put(acc, key, content)

        _ ->
          acc
      end
    end)
  end

  @doc """
  Convert to XML string representation.
  Format: <nodeName attr1="val1" attr2="val2">children</nodeName>
  """
  def to_string(%XmlElement{node_name: tag} = element) do
    attrs = get_attributes(element)

    attr_str =
      attrs
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {name, value} ->
        ~s(#{name}="#{escape_xml_attr(value)}")
      end)
      |> Enum.join(" ")

    children_str =
      element
      |> Type.to_list()
      |> Enum.map(&child_to_string/1)
      |> Enum.join("")

    if attr_str == "" do
      "<#{tag}>#{children_str}</#{tag}>"
    else
      "<#{tag} #{attr_str}>#{children_str}</#{tag}>"
    end
  end

  defp escape_xml_attr(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_xml_attr(value), do: Kernel.to_string(value)

  defp child_to_string(%XmlElement{} = elem), do: XmlElement.to_string(elem)
  defp child_to_string(%Y.Type.XmlText{} = text), do: Y.Type.XmlText.to_string(text)
  defp child_to_string(str) when is_binary(str), do: str
  defp child_to_string(other), do: inspect(other)

  @doc """
  Convert from Unknown type (used during decoding).
  """
  def from_unknown(%Unknown{} = u, node_name) do
    {tree, attrs} =
      u
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.reduce({XmlTree.new(), %{}}, fn item, {tree, attrs} ->
        case item.parent_sub do
          nil ->
            {XmlTree.conj!(tree, item), attrs}

          key ->
            new_attrs = Map.update(attrs, key, [item], fn items -> [item | items] end)
            {tree, new_attrs}
        end
      end)

    # Sort attribute items: live item first, then deleted
    attrs =
      attrs
      |> Enum.map(fn {k, items} ->
        {deleted, live} = Enum.split_with(items, & &1.deleted?)

        case live do
          [head | rest] -> {k, [head | deleted ++ rest]}
          [] -> {k, deleted}
        end
      end)
      |> Enum.into(%{})

    %XmlElement{
      doc_name: u.doc_name,
      name: u.name,
      node_name: node_name,
      tree: tree,
      attributes: attrs
    }
  end

  defdelegate to_list(element), to: Type
  defdelegate to_list(element, opts), to: Type
  defdelegate find(element, id, default \\ nil), to: Type
  defdelegate between(element, left, right), to: Type

  # Y.Type protocol implementation
  defimpl Type do
    def highest_clock(%XmlElement{tree: tree, attributes: attrs}, client) do
      tree_clock = XmlTree.highest_clock(tree, client)

      attr_clock =
        attrs
        |> Map.values()
        |> List.flatten()
        |> then(fn items ->
          case client do
            nil -> items
            client_id -> Enum.reject(items, fn %Item{id: %ID{client: cl}} -> cl != client_id end)
          end
        end)
        |> Enum.reduce(0, fn %Item{id: %ID{clock: clock}}, acc ->
          max(clock, acc)
        end)

      max(tree_clock, attr_clock)
    end

    def highest_clock_with_length(%XmlElement{tree: tree, attributes: attrs}, client) do
      tree_clock = XmlTree.highest_clock_with_length(tree, client)

      attr_clock =
        attrs
        |> Map.values()
        |> List.flatten()
        |> then(fn items ->
          case client do
            nil -> items
            client_id -> Enum.reject(items, fn %Item{id: %ID{client: cl}} -> cl != client_id end)
          end
        end)
        |> Enum.reduce(0, fn %Item{id: %ID{clock: clock}, length: length}, acc ->
          max(clock + length, acc)
        end)

      max(tree_clock, attr_clock)
    end

    def highest_clock_by_client_id(%XmlElement{tree: tree, attributes: attrs}) do
      tree_clocks = XmlTree.highest_clock_by_client_id(tree)

      attr_clocks =
        attrs
        |> Map.values()
        |> List.flatten()
        |> Enum.reduce(%{}, fn item, acc ->
          Map.update(acc, item.id.client, item.id.clock, fn existing ->
            max(existing, item.id.clock)
          end)
        end)

      Map.merge(tree_clocks, attr_clocks, fn _k, v1, v2 -> max(v1, v2) end)
    end

    def highest_clock_with_length_by_client_id(%XmlElement{tree: tree, attributes: attrs}) do
      tree_clocks = XmlTree.highest_clock_with_length_by_client_id(tree)

      attr_clocks =
        attrs
        |> Map.values()
        |> List.flatten()
        |> Enum.reduce(%{}, fn item, acc ->
          Map.update(acc, item.id.client, item.id.clock + Item.content_length(item), fn existing ->
            max(existing, item.id.clock + Item.content_length(item))
          end)
        end)

      Map.merge(tree_clocks, attr_clocks, fn _k, v1, v2 -> max(v1, v2) end)
    end

    def pack(%XmlElement{tree: tree, attributes: attrs} = element) do
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

      new_attrs =
        attrs
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

      %{element | tree: new_tree, attributes: new_attrs}
    end

    def to_list(%XmlElement{tree: tree}, opts \\ []) do
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

    def find(%XmlElement{tree: tree, attributes: attrs}, %ID{} = id, default) do
      # First try the tree
      case XmlTree.find(tree, id, nil) do
        nil ->
          # Then try attributes
          attrs
          |> Map.values()
          |> List.flatten()
          |> Enum.find(default, fn %Item{id: i_id} -> i_id == id end)

        item ->
          item
      end
    end

    def unsafe_replace(
          %XmlElement{tree: tree} = element,
          %Item{id: %ID{clock: item_clock}, parent_sub: nil} = item,
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
            {:ok, new_tree} -> {:ok, %{element | tree: new_tree}}
            err -> err
          end
      end
    end

    def unsafe_replace(
          %XmlElement{attributes: attrs} = element,
          %Item{id: %ID{clock: item_clock}, parent_sub: parent_sub} = item,
          with_items
        )
        when is_list(with_items) and not is_nil(parent_sub) do
      [%{id: %ID{clock: f_clock}} | _] = with_items

      with_items_length =
        Enum.reduce(with_items, 0, fn i, acc -> acc + Item.content_length(i) end)

      with_items_parent_sub = Enum.map(with_items, & &1.parent_sub) |> Enum.uniq()

      cond do
        f_clock != item_clock ->
          {:error, "Clocks diverge"}

        Item.content_length(item) != with_items_length ->
          {:error, "Total content length of items != length of item to replace"}

        Map.has_key?(attrs, parent_sub) == false ->
          {:error, "Item's parent_sub key is missing in attributes"}

        [parent_sub] != with_items_parent_sub ->
          {:error, "Some item(s) to replace has different parent_sub"}

        :otherwise ->
          new_attrs =
            Map.update!(attrs, parent_sub, fn items ->
              items
              |> Enum.reverse()
              |> Enum.flat_map(fn next_item ->
                if next_item == item, do: with_items, else: [next_item]
              end)
            end)

          if Map.fetch!(new_attrs, parent_sub) == Map.fetch!(attrs, parent_sub) do
            {:error, "Item not found"}
          else
            {:ok, %{element | attributes: new_attrs}}
          end
      end
    end

    def between(%XmlElement{tree: tree}, %ID{} = left, %ID{} = right) do
      XmlTree.between(tree, left, right)
    end

    def add_after(%XmlElement{tree: tree} = element, %Item{} = after_item, %Item{} = item) do
      case XmlTree.add_after(tree, after_item, item) do
        {:ok, new_tree} -> {:ok, %{element | tree: new_tree}}
        err -> err
      end
    end

    def add_before(%XmlElement{tree: tree} = element, nil, %Item{} = item) do
      case XmlTree.put(tree, 0, item) do
        {:ok, tree} -> {:ok, %{element | tree: tree}}
        err -> err
      end
    end

    def add_before(%XmlElement{tree: tree} = element, %Item{} = before_item, %Item{} = item) do
      case XmlTree.add_before(tree, before_item, item) do
        {:ok, tree} -> {:ok, %{element | tree: tree}}
        err -> err
      end
    end

    def next(%XmlElement{tree: tree}, %Item{} = item) do
      XmlTree.next(tree, item)
    end

    def prev(%XmlElement{tree: tree}, %Item{} = item) do
      XmlTree.prev(tree, item)
    end

    def first(%XmlElement{tree: tree}, _) do
      XmlTree.first(tree)
    end

    def last(%XmlElement{tree: tree}, _) do
      XmlTree.last(tree)
    end

    def delete(%XmlElement{tree: tree} = element, %Transaction{} = transaction, %ID{} = id) do
      case XmlTree.find(tree, id) do
        nil ->
          Logger.warning("Fail to find item to delete", element: element, id: id)
          {:ok, transaction}

        %Item{} = starting_item ->
          with {:ok, new_tree} <-
                 XmlTree.transform(tree, starting_item, 0, fn item, pos ->
                   if pos < 1, do: {Item.delete(item), pos + 1}
                 end),
               {:ok, transaction} <-
                 Transaction.update(transaction, %{element | tree: new_tree}) do
            {:ok, %{element | tree: new_tree}, transaction}
          end
      end
    end

    def type_ref(_), do: 3

    def gc(%XmlElement{tree: tree, attributes: attrs} = element) do
      new_tree =
        element
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

      new_attrs =
        attrs
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

      %{element | tree: new_tree, attributes: new_attrs}
    end
  end
end
