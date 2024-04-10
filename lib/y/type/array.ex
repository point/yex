defmodule Y.Type.Array do
  alias __MODULE__
  alias Y.Type.Array.ArrayTree
  alias Y.Type.Unknown
  alias Y.Type
  alias Y.Transaction
  alias Y.Doc
  alias Y.Item
  alias Y.ID

  require Logger

  defstruct tree: nil,
            doc_name: nil,
            name: nil

  def new(%Doc{name: doc_name}, name) do
    %Array{doc_name: doc_name, name: name, tree: ArrayTree.new()}
  end

  def put({:ok, %Array{} = array, %Transaction{} = transaction}, index, content),
    do: put(array, transaction, index, content)

  def put(array, %Transaction{} = transaction, index, content) do
    do_put_many(array, transaction, index, [content])
  end

  def put_many({:ok, %Array{} = array, %Transaction{} = transaction}, index, content),
    do: put_many(array, transaction, index, content)

  def put_many(%Array{} = array, %Transaction{} = transaction, index, content)
      when is_list(content) do
    content
    |> Enum.chunk_by(fn e -> is_struct(e) end)
    |> Enum.reverse()
    |> Enum.reduce_while({array, transaction}, fn c, {array, transaction} ->
      case do_put_many(array, transaction, index, c) do
        {:ok, new_array, new_transaction} -> {:cont, {new_array, new_transaction}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {%Array{} = array, %Transaction{} = transaction} -> {:ok, array, transaction}
      err -> err
    end
  end

  # def to_list(array), do: Type.to_list(array, as_items: false)
  defdelegate to_list(array), to: Type
  defdelegate to_list(array, opts), to: Type

  defdelegate find(array, id, default \\ nil), to: Type

  defdelegate between(array, left, right), to: Type

  def from_unknown(%Unknown{} = u) do
    tree =
      u
      |> Type.to_list(as_items: true)
      |> Enum.reduce(ArrayTree.new(), fn item, tree ->
        ArrayTree.conj!(tree, item)
      end)

    %Array{doc_name: u.doc_name, name: u.name, tree: tree}
  end

  def length(%Array{tree: tree}), do: ArrayTree.length(tree)

  def at(%Array{tree: tree}, index), do: ArrayTree.at(tree, index)

  def delete(array, transaction, index, length \\ 1)
  def delete(%Array{} = _array, %Transaction{} = transaction, _index, 0), do: {:ok, transaction}

  def delete(%Array{tree: tree} = array, %Transaction{} = transaction, index, length) do
    case ArrayTree.at(tree, index) do
      nil ->
        Logger.warning("Fail to find item to delete at position", array: array, index: index)
        {:ok, transaction}

      %Item{} = starting_item ->
        do_delete(array, transaction, starting_item, length)
    end
  end

  def delete_by_id(%Array{tree: tree} = array, %Transaction{} = transaction, %ID{} = id) do
    case ArrayTree.find(tree, id) do
      nil ->
        Logger.warning("Fail to find item to delete", array: array, id: id)
        {:ok, transaction}

      %Item{} = starting_item ->
        do_delete(array, transaction, starting_item, 1)
    end
  end

  defp do_delete(array, transaction, starting_item, length) do
    with {:ok, new_array_tree} <-
           ArrayTree.transform(array.tree, starting_item, 0, fn item, pos ->
             if pos < length, do: {Item.delete(item), pos + 1}
           end),
         {:ok, transaction} <-
           Transaction.update(transaction, %Array{array | tree: new_array_tree}) do
      {:ok, %{array | tree: new_array_tree}, transaction}
    else
      _ ->
        Logger.warning("Fail to delete item(s)",
          array: array,
          starting_item: starting_item,
          length: length
        )

        {:error, array, transaction}
    end
  end

  defp do_put_many(
         %Array{tree: tree, name: parent_name} = array,
         %Transaction{doc: doc} = transaction,
         index,
         content
       )
       when is_list(content) do
    clock_length = Doc.highest_clock_with_length(transaction)

    item =
      Item.new(
        id: ID.new(doc.client_id, clock_length),
        content: content,
        parent_name: parent_name
      )

    with {:ok, new_tree} <- ArrayTree.put(tree, index, item),
         new_array = %{array | tree: new_tree},
         {:ok, new_transaction} <- Transaction.update(transaction, new_array) do
      {:ok, new_array, new_transaction}
    end
  end

  defimpl Type do
    def highest_clock(%Array{tree: tree}, client), do: ArrayTree.highest_clock(tree, client)

    def highest_clock_with_length(%Array{tree: tree}, client),
      do: ArrayTree.highest_clock_with_length(tree, client)

    def pack(%Array{tree: tree} = array) do
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
        |> Enum.into(ArrayTree.new())

      %{array | tree: new_tree}
    end

    def to_list(%Array{tree: tree}, opts \\ []) do
      as_items = Keyword.get(opts, :as_items, false)
      with_deleted = Keyword.get(opts, :with_deleted, false)

      items =
        if with_deleted do
          ArrayTree.to_list(tree)
        else
          ArrayTree.to_list(tree) |> Enum.reject(& &1.deleted?)
        end

      if as_items, do: items, else: items |> Enum.map(& &1.content) |> List.flatten()
    end

    # def to_list(%Array{tree: tree}, as_items: false),
    #   do: tree |> ArrayTree.to_list() |> Enum.map(& &1.content) |> List.flatten()
    #
    # def to_list(%Array{tree: tree}, as_items: true), do: tree |> ArrayTree.to_list()

    def find(%Array{tree: tree}, %ID{} = id, default), do: tree |> ArrayTree.find(id, default)

    def unsafe_replace(
          %Array{tree: tree} = array,
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
          %{array | tree: ArrayTree.replace(tree, item, with_items)}
      end
    end

    def between(%Array{tree: tree}, %ID{} = left, %ID{} = right) do
      ArrayTree.between(tree, left, right)
    end

    def add_after(%Array{tree: tree} = array, %Item{} = after_item, %Item{} = item) do
      case ArrayTree.add_after(tree, after_item, item) do
        {:ok, new_tree} -> {:ok, %{array | tree: new_tree}}
        err -> err
      end
    end

    def add_before(%Array{tree: tree} = array, nil, %Item{} = item),
      do: {:ok, %{array | tree: ArrayTree.put(tree, 0, item)}}

    def add_before(%Array{tree: tree} = array, %Item{} = before_item, %Item{} = item) do
      case ArrayTree.add_before(tree, before_item, item) do
        {:ok, tree} -> {:ok, %{array | tree: tree}}
        err -> err
      end
    end

    def next(%Array{tree: tree}, %Item{} = item) do
      ArrayTree.next(tree, item)
    end

    def prev(%Array{tree: tree}, %Item{} = item) do
      ArrayTree.prev(tree, item)
    end

    def first(%Array{tree: tree}) do
      ArrayTree.first(tree)
    end

    def last(%Array{tree: tree}) do
      ArrayTree.last(tree)
    end

    defdelegate delete(array, transaction, id), to: Y.Type.Array, as: :delete_by_id
  end

  defimpl Enumerable do
    def count(_) do
      {:error, __MODULE__}
    end

    def member?(_array, _element) do
      {:error, __MODULE__}
    end

    # def reduce0(%Array{tree: tree} = array, {:cont, acc}, fun) do
    #   reduce_item = fn
    #     _, {:halt, acc}, _, _ ->
    #       {:halted, acc}
    #
    #     [], {:cont, acc}, _fun, _ ->
    #       {:cont, acc}
    #
    #     [c | rest], {:cont, acc}, fun, reduce_item ->
    #       reduce_item.(rest, fun.(c, acc), fun, reduce_item)
    #   end
    #
    #   case ArrayTree.first(tree) do
    #     nil ->
    #       {:done, acc}
    #
    #     %{deleted?: true} ->
    #       reduce(%{array | tree: ArrayTree.rest(tree)}, {:cont, acc}, fun)
    #
    #     %{content: content} ->
    #       reduce(
    #         %{array | tree: ArrayTree.rest(tree)},
    #         reduce_item.(content, {:cont, acc}, fun, reduce_item),
    #         fun
    #       )
    #   end
    # end

    def reduce(array, acc, fun)

    def reduce(%Array{tree: tree}, {:cont, acc}, fun) do
      Enumerable.reduce(tree, {:cont, acc}, fn
        nil, acc ->
          {:done, acc}

        %{deleted?: true}, acc ->
          {:cont, acc}

        %{content: content}, acc ->
          Enum.reduce_while(content, {:cont, acc}, fn c, {_, acc} ->
            case fun.(c, acc) do
              {:cont, _acc} = r -> {:cont, r}
              {:halt, _acc} = r -> {:halt, r}
            end
          end)
      end)
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
