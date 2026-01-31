defmodule Y.UndoManager.StackItem do
  @moduledoc """
  Represents a single undo/redo step.

  Contains:
  - insertions: Set of IDs that were inserted (to be deleted on undo)
  - deletions: Set of IDs that were deleted (to be restored on undo)
  - meta: User-defined metadata Map
  """

  alias __MODULE__

  defstruct insertions: %{},
            deletions: %{},
            meta: %{}

  @type id_set :: %{optional(non_neg_integer()) => MapSet.t({non_neg_integer(), non_neg_integer()})}
  @type t :: %StackItem{
          insertions: id_set(),
          deletions: id_set(),
          meta: map()
        }

  @doc """
  Create a new StackItem.
  """
  def new(opts \\ []) do
    %StackItem{
      insertions: Keyword.get(opts, :insertions, %{}),
      deletions: Keyword.get(opts, :deletions, %{}),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @doc """
  Add an insertion to the stack item.
  """
  def add_insertion(%StackItem{insertions: insertions} = stack_item, client, clock, length) do
    new_insertions =
      Map.update(insertions, client, MapSet.new([{clock, length}]), fn set ->
        MapSet.put(set, {clock, length})
      end)

    %{stack_item | insertions: new_insertions}
  end

  @doc """
  Add a deletion to the stack item.
  """
  def add_deletion(%StackItem{deletions: deletions} = stack_item, client, clock, length) do
    new_deletions =
      Map.update(deletions, client, MapSet.new([{clock, length}]), fn set ->
        MapSet.put(set, {clock, length})
      end)

    %{stack_item | deletions: new_deletions}
  end

  @doc """
  Merge two stack items.
  Combines insertions and deletions from both items.
  """
  def merge(%StackItem{} = item1, %StackItem{} = item2) do
    %StackItem{
      insertions: merge_id_sets(item1.insertions, item2.insertions),
      deletions: merge_id_sets(item1.deletions, item2.deletions),
      meta: Map.merge(item1.meta, item2.meta)
    }
  end

  @doc """
  Check if the stack item is empty (no insertions and no deletions).
  """
  def empty?(%StackItem{insertions: insertions, deletions: deletions}) do
    map_size(insertions) == 0 and map_size(deletions) == 0
  end

  @doc """
  Create a stack item from a transaction.
  Extracts insertions from newly added items and deletions from delete_set.
  """
  def from_transaction(transaction, tracked_types, client_id) do
    # Get items that were inserted during this transaction
    insertions = extract_insertions(transaction, tracked_types, client_id)

    # Get items that were deleted during this transaction
    deletions = extract_deletions(transaction, tracked_types)

    new(insertions: insertions, deletions: deletions)
  end

  # Extract insertions: items added by this client in tracked types
  defp extract_insertions(transaction, tracked_types, client_id) do
    transaction.doc.share
    |> Enum.filter(fn {name, _type} -> name in tracked_types end)
    |> Enum.flat_map(fn {_name, type} ->
      type
      |> Y.Type.to_list(as_items: true, with_deleted: false)
      |> Enum.filter(fn item ->
        item.id.client == client_id and
          was_inserted_in_transaction?(item, transaction)
      end)
    end)
    |> Enum.reduce(%{}, fn item, acc ->
      Map.update(acc, item.id.client, MapSet.new([{item.id.clock, item.length}]), fn set ->
        MapSet.put(set, {item.id.clock, item.length})
      end)
    end)
  end

  # Check if an item was inserted during this transaction
  # by comparing its clock with the before_state
  defp was_inserted_in_transaction?(item, transaction) do
    case Map.get(transaction.before_state || %{}, item.id.client) do
      nil -> true
      before_clock -> item.id.clock >= before_clock
    end
  end

  # Extract deletions from the transaction's delete_set
  defp extract_deletions(transaction, _tracked_types) do
    transaction.delete_set
    |> Enum.map(fn {client, clock_set} ->
      {client,
       clock_set
       |> Enum.map(fn {clock, length} -> {clock, length} end)
       |> MapSet.new()}
    end)
    |> Enum.into(%{})
  end

  # Merge two id_sets
  defp merge_id_sets(set1, set2) do
    Map.merge(set1, set2, fn _client, items1, items2 ->
      MapSet.union(items1, items2)
    end)
  end
end
