defmodule Y.Type.Text do
  alias __MODULE__
  alias Y.Doc
  alias Y.Type
  alias Y.Type.Text.Tree
  alias Y.Type.Unknown
  alias Y.Content.Format
  alias Y.Content.Deleted
  alias Y.Content.String, as: ContentString
  alias Y.Item
  alias Y.ID
  alias Y.Transaction

  require Logger

  defstruct tree: nil,
            doc_name: nil,
            name: nil

  def new(%Doc{name: doc_name}, name \\ UUID.uuid4()) do
    %Text{doc_name: doc_name, name: name, tree: Tree.new()}
  end

  def insert(
        %Text{tree: tree} = type_text,
        %Transaction{} = transaction,
        index,
        text,
        attributes \\ %{}
      ) do
    # Must get clock for THIS client only, not the max across all clients
    with last_clock = Doc.highest_clock_with_length(transaction, transaction.doc.client_id),
         %Tree{} = new_tree <-
           Tree.insert(
             tree,
             index,
             text,
             attributes,
             type_text.name,
             transaction.doc.client_id,
             last_clock
           ),
         new_type_text = %{type_text | tree: new_tree},
         {:ok, new_transaction} <- Transaction.update(transaction, new_type_text) do
      {:ok, new_type_text, new_transaction}
    end
  end

  def delete(text, transaction, index, length \\ 1)
  def delete(_text, transaction, _index, 0), do: {:ok, transaction}

  def delete(%Text{} = text, %Transaction{} = transaction, index, length) do
    with new_text = %{text | tree: Tree.delete(text.tree, index, length)},
         {:ok, transaction} <- Transaction.update(transaction, new_text) do
      {:ok, new_text, transaction}
    else
      _ ->
        Logger.warning("Fail to delete item(s)",
          text: text,
          index: index,
          length: length
        )

        {:error, text, transaction}
    end
  end

  def delete_by_id(%Text{tree: tree} = text, %Transaction{} = transaction, %ID{} = id) do
    case Tree.find_index(tree, id) do
      nil -> {:error, text, transaction}
      idx -> Text.delete(text, transaction, idx)
    end
  end

  def to_string(%Text{} = text) do
    to_list(text)
    |> Enum.reject(&match?(%Format{}, &1))
    |> Enum.join()
  end

  def from_unknown(%Unknown{} = u) do
    tree =
      u
      |> Type.to_list(as_items: true, with_deleted: true)
      |> Enum.reduce(Tree.new(), fn item, tree ->
        Tree.conj!(tree, item)
      end)

    %Text{doc_name: u.doc_name, name: u.name, tree: tree}
  end

  defdelegate to_list(text), to: Type
  defdelegate to_list(text, opts), to: Type

  defimpl Type do
    def highest_clock(%Text{tree: tree}, client), do: Tree.highest_clock(tree, client)

    def highest_clock_with_length(%Text{tree: tree}, client),
      do: Tree.highest_clock_with_length(tree, client)

    def highest_clock_by_client_id(%Text{tree: tree}),
      do: Tree.highest_clock_by_client_id(tree)

    def highest_clock_with_length_by_client_id(%Text{tree: tree}),
      do: Tree.highest_clock_with_length_by_client_id(tree)

    def pack(%Text{tree: tree} = text) do
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
        |> Enum.map(fn %Item{content: content} = item ->
          if length(content) > 1 &&
               Enum.all?(content, fn c -> String.valid?(c) && String.length(c) == 1 end) do
            %{item | content: ContentString.new(content)}
          else
            item
          end
        end)
        |> Enum.into(Tree.new())

      %{text | tree: new_tree}
    end

    def to_list(%Text{tree: tree}, opts \\ []) do
      as_items = Keyword.get(opts, :as_items, false)
      with_deleted = Keyword.get(opts, :with_deleted, false)

      items =
        if with_deleted do
          Tree.to_list(tree)
        else
          Tree.to_list(tree) |> Enum.reject(& &1.deleted?)
        end

      if as_items, do: items, else: items |> Enum.map(& &1.content) |> List.flatten()
    end

    def find(%Text{tree: tree}, %ID{} = id, default) do
      tree |> Tree.find(id, default)
    end

    def unsafe_replace(
          %Text{tree: tree} = text,
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
            {:ok, new_tree} -> {:ok, %{text | tree: new_tree}}
            err -> err
          end
      end
    end

    def between(%Text{tree: tree}, %ID{} = left, %ID{} = right) do
      Tree.between(tree, left, right)
    end

    def add_after(%Text{tree: tree} = text, %Item{} = after_item, %Item{} = item) do
      case Tree.add_after(tree, after_item, item) do
        {:ok, new_tree} -> {:ok, %{text | tree: new_tree}}
        err -> err
      end
    end

    def add_before(%Text{tree: tree} = text, %Item{} = before_item, %Item{} = item) do
      case Tree.add_before(tree, before_item, item) do
        {:ok, tree} -> {:ok, %{text | tree: tree}}
        err -> err
      end
    end

    def next(%Text{tree: tree}, %Item{} = item) do
      Tree.next(tree, item)
    end

    def prev(%Text{tree: tree}, %Item{} = item) do
      Tree.prev(tree, item)
    end

    def first(%Text{tree: tree}, _) do
      Tree.first(tree)
    end

    def last(%Text{tree: tree}, _) do
      Tree.last(tree)
    end

    # defdelegate delete(text, transaction, id), to: Y.Type.Array, as: :delete_by_id

    def type_ref(_), do: 0

    def gc(%Text{tree: tree} = text) do
      new_tree =
        text
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

      %{text | tree: new_tree}
    end

    def delete(%Text{} = text, transaction, id), do: Text.delete_by_id(text, transaction, id)
  end

  # defimpl Enumerable do
  #   def count(_) do
  #     {:error, __MODULE__}
  #   end
  #
  #   def member?(_array, _element) do
  #     {:error, __MODULE__}
  #   end
  #
  #   def reduce(array, acc, fun)
  #
  #   def reduce(%Text{tree: tree}, {:cont, acc}, fun) do
  #     Enumerable.reduce(tree, {:cont, acc}, fn
  #       nil, acc ->
  #         {:done, acc}
  #
  #       %{deleted?: true}, acc ->
  #         {:cont, acc}
  #
  #       %{content: content}, acc ->
  #         Enum.reduce_while(content, {:cont, acc}, fn c, {_, acc} ->
  #           case fun.(c, acc) do
  #             {:cont, _acc} = r -> {:cont, r}
  #             {:halt, _acc} = r -> {:halt, r}
  #           end
  #         end)
  #     end)
  #   end
  #
  #   def reduce(_array, {:halt, acc}, _fun) do
  #     {:halted, acc}
  #   end
  #
  #   def reduce(array, {:suspend, acc}, fun) do
  #     {:suspended, acc, &reduce(array, &1, fun)}
  #   end
  #
  #   def slice(_) do
  #     {:error, __MODULE__}
  #   end
  # end
end
