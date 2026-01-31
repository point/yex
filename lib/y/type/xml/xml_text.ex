defmodule Y.Type.XmlText do
  @moduledoc """
  XML Text type - represents text content within XML elements.
  Similar to YXmlText in Y.js.

  XmlText wraps the Text type to provide text nodes in XML documents.
  It supports the same formatting capabilities as Text.
  """

  alias __MODULE__
  alias Y.Doc
  alias Y.Type
  alias Y.Type.Text.Tree
  alias Y.Type.Unknown
  alias Y.Content.Format
  alias Y.Content.Deleted
  alias Y.Item
  alias Y.ID
  alias Y.Transaction

  require Logger

  defstruct tree: nil,
            doc_name: nil,
            name: nil

  @doc """
  Create a new XmlText.
  """
  def new(%Doc{name: doc_name}, name \\ UUID.uuid4()) do
    %XmlText{doc_name: doc_name, name: name, tree: Tree.new()}
  end

  @doc """
  Insert text at the given index with optional attributes.
  """
  def insert(
        %XmlText{tree: tree} = xml_text,
        %Transaction{} = transaction,
        index,
        text,
        attributes \\ %{}
      ) do
    with last_clock = Doc.highest_clock_with_length(transaction, transaction.doc.client_id),
         %Tree{} = new_tree <-
           Tree.insert(
             tree,
             index,
             text,
             attributes,
             xml_text.name,
             transaction.doc.client_id,
             last_clock
           ),
         new_xml_text = %{xml_text | tree: new_tree},
         {:ok, new_transaction} <- Transaction.update(transaction, new_xml_text) do
      {:ok, new_xml_text, new_transaction}
    end
  end

  @doc """
  Delete text at the given index.
  """
  def delete(xml_text, transaction, index, length \\ 1)
  def delete(_xml_text, transaction, _index, 0), do: {:ok, transaction}

  def delete(%XmlText{} = xml_text, %Transaction{} = transaction, index, length) do
    with new_xml_text = %{xml_text | tree: Tree.delete(xml_text.tree, index, length)},
         {:ok, transaction} <- Transaction.update(transaction, new_xml_text) do
      {:ok, new_xml_text, transaction}
    else
      _ ->
        Logger.warning("Fail to delete item(s)",
          xml_text: xml_text,
          index: index,
          length: length
        )

        {:error, xml_text, transaction}
    end
  end

  @doc """
  Format a range of text with the given attributes.

  ## Parameters
  - xml_text: The XmlText type
  - transaction: The current transaction
  - index: The starting index of the range to format
  - length: The length of the range to format
  - attributes: A map of attributes to apply (e.g., %{bold: true, italic: true})

  ## Returns
  `{:ok, new_xml_text, new_transaction}` on success
  """
  def format(
        %XmlText{tree: tree} = xml_text,
        %Transaction{} = transaction,
        index,
        length,
        attributes
      )
      when is_map(attributes) and length > 0 do
    with last_clock = Doc.highest_clock_with_length(transaction, transaction.doc.client_id),
         %Tree{} = new_tree <-
           Tree.format(
             tree,
             index,
             length,
             attributes,
             xml_text.name,
             transaction.doc.client_id,
             last_clock
           ),
         new_xml_text = %{xml_text | tree: new_tree},
         {:ok, new_transaction} <- Transaction.update(transaction, new_xml_text) do
      {:ok, new_xml_text, new_transaction}
    end
  end

  def format(%XmlText{} = xml_text, %Transaction{} = transaction, _index, 0, _attributes) do
    {:ok, xml_text, transaction}
  end

  @doc """
  Delete text by item ID.
  """
  def delete_by_id(%XmlText{tree: tree} = xml_text, %Transaction{} = transaction, %ID{} = id) do
    case Tree.find_index(tree, id) do
      nil -> {:error, xml_text, transaction}
      idx -> XmlText.delete(xml_text, transaction, idx)
    end
  end

  @doc """
  Convert to plain string (without formatting).
  """
  def to_string(%XmlText{} = xml_text) do
    to_list(xml_text)
    |> Enum.reject(&match?(%Format{}, &1))
    |> Enum.join()
  end

  @doc """
  Convert the xml text to a delta format (list of operations with attributes).

  Returns a list of maps, each with:
  - `:insert` - the text content
  - `:attributes` - (optional) map of attributes if any are applied

  Example:
  ```
  [
    %{insert: "hello", attributes: %{bold: true}},
    %{insert: " world"}
  ]
  ```
  """
  def to_delta(%XmlText{} = xml_text) do
    items = to_list(xml_text, as_items: true)

    # Track current attributes as we iterate
    {result, final_attrs, final_pending_text} =
      items
      |> Enum.reduce({[], %{}, ""}, fn item, {result, current_attrs, pending_text} ->
        case item do
          %Item{content: [%Format{key: key, value: value}], deleted?: false} ->
            # Flush pending text before attribute change
            result =
              if pending_text != "" do
                entry =
                  if map_size(current_attrs) > 0 do
                    %{insert: pending_text, attributes: current_attrs}
                  else
                    %{insert: pending_text}
                  end

                result ++ [entry]
              else
                result
              end

            # Update current attributes
            new_attrs =
              if is_nil(value) do
                Map.delete(current_attrs, key)
              else
                Map.put(current_attrs, key, value)
              end

            {result, new_attrs, ""}

          %Item{deleted?: false, content: content} ->
            # Accumulate text content
            text_content =
              content
              |> Enum.reject(&match?(%Format{}, &1))
              |> Enum.join()

            {result, current_attrs, pending_text <> text_content}

          _ ->
            {result, current_attrs, pending_text}
        end
      end)

    # Flush any remaining pending text
    if final_pending_text != "" do
      entry =
        if map_size(final_attrs) > 0 do
          %{insert: final_pending_text, attributes: final_attrs}
        else
          %{insert: final_pending_text}
        end

      result ++ [entry]
    else
      result
    end
  end

  @doc """
  Convert from Unknown type (used during decoding).
  """
  def from_unknown(%Unknown{} = u) do
    tree =
      u
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.reduce(Tree.new(), fn item, tree ->
        Tree.conj!(tree, item)
      end)

    %XmlText{doc_name: u.doc_name, name: u.name, tree: tree}
  end

  defdelegate to_list(xml_text), to: Type
  defdelegate to_list(xml_text, opts), to: Type

  # Y.Type protocol implementation
  defimpl Type do
    def highest_clock(%XmlText{tree: tree}, client), do: Tree.highest_clock(tree, client)

    def highest_clock_with_length(%XmlText{tree: tree}, client),
      do: Tree.highest_clock_with_length(tree, client)

    def highest_clock_by_client_id(%XmlText{tree: tree}),
      do: Tree.highest_clock_by_client_id(tree)

    def highest_clock_with_length_by_client_id(%XmlText{tree: tree}),
      do: Tree.highest_clock_with_length_by_client_id(tree)

    def pack(%XmlText{tree: tree} = xml_text) do
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
        |> Enum.into(Tree.new())

      %{xml_text | tree: new_tree}
    end

    def to_list(%XmlText{tree: tree}, opts \\ []) do
      as_items = Keyword.get(opts, :as_items, false)
      with_deleted = Keyword.get(opts, :with_deleted, false)

      items =
        if with_deleted do
          Tree.to_list(tree)
        else
          Tree.to_list(tree) |> Enum.reject(& &1.deleted?)
        end

      if as_items,
        do: items,
        else:
          items
          |> Enum.map(fn item -> item.content end)
          |> List.flatten()
    end

    def find(%XmlText{tree: tree}, %ID{} = id, default), do: tree |> Tree.find(id, default)

    def unsafe_replace(
          %XmlText{tree: tree} = xml_text,
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
          case Tree.replace(tree, item, with_items) do
            {:ok, new_tree} -> {:ok, %{xml_text | tree: new_tree}}
            err -> err
          end
      end
    end

    def between(%XmlText{tree: tree}, %ID{} = left, %ID{} = right) do
      Tree.between(tree, left, right)
    end

    def add_after(%XmlText{tree: tree} = xml_text, %Item{} = after_item, %Item{} = item) do
      case Tree.add_after(tree, after_item, item) do
        {:ok, new_tree} -> {:ok, %{xml_text | tree: new_tree}}
        err -> err
      end
    end

    def add_before(%XmlText{tree: tree} = xml_text, before_item, %Item{} = item) do
      case Tree.add_before(tree, before_item, item) do
        {:ok, tree} -> {:ok, %{xml_text | tree: tree}}
        err -> err
      end
    end

    def next(%XmlText{tree: tree}, %Item{} = item) do
      Tree.next(tree, item)
    end

    def prev(%XmlText{tree: tree}, %Item{} = item) do
      Tree.prev(tree, item)
    end

    def first(%XmlText{tree: tree}, _) do
      Tree.first(tree)
    end

    def last(%XmlText{tree: tree}, _) do
      Tree.last(tree)
    end

    def delete(%XmlText{} = xml_text, %Transaction{} = transaction, %ID{} = id) do
      XmlText.delete_by_id(xml_text, transaction, id)
    end

    def type_ref(_), do: 6

    def gc(%XmlText{tree: tree} = xml_text) do
      new_tree =
        xml_text
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
              with %Item{} = item <- Tree.find(tree, deleted_item.id),
                   {:ok, new_tree} <-
                     Tree.replace(tree, item, [%{item | content: [Deleted.from_item(item)]}]) do
                new_tree
              else
                _ -> tree
              end
            end)
        end

      %{xml_text | tree: new_tree}
    end
  end
end
