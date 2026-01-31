defmodule Y.UndoManager do
  @moduledoc """
  UndoManager tracks changes to specific Y types and allows undo/redo operations.

  Features:
  - Undo/redo stacks for tracking changes
  - Capture timeout for batching rapid edits
  - Tracked origins to filter which transactions to capture
  - Integration with Doc transactions via observer pattern

  ## Usage

      {:ok, doc} = Y.Doc.new(name: :my_doc)
      {:ok, text} = Y.Doc.get_text(doc, "text")

      # Create undo manager tracking the text type
      {:ok, undo_manager} = Y.UndoManager.new(doc, ["text"])

      # Make changes
      Y.Doc.transact(doc, fn t ->
        {:ok, text, t} = Y.Type.Text.insert(text, t, 0, "hello")
        {:ok, t}
      end)

      # Undo the change
      Y.UndoManager.undo(undo_manager)

  """

  use GenServer

  alias Y.UndoManager.StackItem
  alias Y.Doc
  alias Y.Transaction
  alias Y.Item
  alias Y.ID

  require Logger

  defstruct doc_name: nil,
            tracked_types: [],
            tracked_origins: nil,
            undo_stack: [],
            redo_stack: [],
            capture_timeout: 500,
            last_change: 0,
            capturing: true,
            undoing: false,
            redoing: false

  @type t :: %__MODULE__{
          doc_name: atom(),
          tracked_types: [String.t()],
          tracked_origins: MapSet.t() | nil,
          undo_stack: [StackItem.t()],
          redo_stack: [StackItem.t()],
          capture_timeout: non_neg_integer(),
          last_change: non_neg_integer(),
          capturing: boolean(),
          undoing: boolean(),
          redoing: boolean()
        }

  # Client API

  @doc """
  Create a new UndoManager for a document.

  ## Options

  - `:capture_timeout` - Time in ms to batch rapid edits (default: 500)
  - `:tracked_origins` - Set of transaction origins to track (default: nil = track all local)
  """
  def new(doc_name, tracked_types, opts \\ []) when is_list(tracked_types) do
    GenServer.start_link(__MODULE__, {doc_name, tracked_types, opts})
  end

  @doc """
  Undo the last change.
  Returns :ok if successful, :nothing_to_undo if stack is empty.
  """
  def undo(undo_manager) do
    GenServer.call(undo_manager, :undo)
  end

  @doc """
  Redo the last undone change.
  Returns :ok if successful, :nothing_to_redo if stack is empty.
  """
  def redo(undo_manager) do
    GenServer.call(undo_manager, :redo)
  end

  @doc """
  Stop capturing changes into the current stack item.
  Forces the next change to create a new undo step.
  """
  def stop_capturing(undo_manager) do
    GenServer.call(undo_manager, :stop_capturing)
  end

  @doc """
  Clear the undo and/or redo stacks.

  ## Options

  - `:undo` - Clear undo stack (default: true)
  - `:redo` - Clear redo stack (default: true)
  """
  def clear(undo_manager, opts \\ []) do
    GenServer.call(undo_manager, {:clear, opts})
  end

  @doc """
  Check if there are changes to undo.
  """
  def can_undo?(undo_manager) do
    GenServer.call(undo_manager, :can_undo?)
  end

  @doc """
  Check if there are changes to redo.
  """
  def can_redo?(undo_manager) do
    GenServer.call(undo_manager, :can_redo?)
  end

  @doc """
  Get the length of the undo stack.
  """
  def undo_stack_length(undo_manager) do
    GenServer.call(undo_manager, :undo_stack_length)
  end

  @doc """
  Get the length of the redo stack.
  """
  def redo_stack_length(undo_manager) do
    GenServer.call(undo_manager, :redo_stack_length)
  end

  # GenServer Callbacks

  @impl true
  def init({doc_name, tracked_types, opts}) do
    capture_timeout = Keyword.get(opts, :capture_timeout, 500)

    tracked_origins =
      case Keyword.get(opts, :tracked_origins) do
        nil -> nil
        origins when is_list(origins) -> MapSet.new(origins)
        %MapSet{} = set -> set
      end

    state = %__MODULE__{
      doc_name: doc_name,
      tracked_types: tracked_types,
      tracked_origins: tracked_origins,
      capture_timeout: capture_timeout,
      undo_stack: [],
      redo_stack: [],
      last_change: 0,
      capturing: true,
      undoing: false,
      redoing: false
    }

    # Subscribe to transaction events from the doc
    Doc.subscribe_transaction(doc_name, self())

    {:ok, state}
  end

  @impl true
  def handle_call(:undo, _from, %{undo_stack: []} = state) do
    {:reply, :nothing_to_undo, state}
  end

  def handle_call(:undo, _from, %{undo_stack: [stack_item | rest]} = state) do
    # Apply the undo
    state = %{state | undoing: true}

    case apply_undo(stack_item, state) do
      {:ok, redo_item} ->
        new_state = %{
          state
          | undo_stack: rest,
            redo_stack: [redo_item | state.redo_stack],
            undoing: false,
            last_change: 0
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.warning("Undo failed: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | undoing: false}}
    end
  end

  @impl true
  def handle_call(:redo, _from, %{redo_stack: []} = state) do
    {:reply, :nothing_to_redo, state}
  end

  def handle_call(:redo, _from, %{redo_stack: [stack_item | rest]} = state) do
    # Apply the redo
    state = %{state | redoing: true}

    case apply_redo(stack_item, state) do
      {:ok, undo_item} ->
        new_state = %{
          state
          | redo_stack: rest,
            undo_stack: [undo_item | state.undo_stack],
            redoing: false,
            last_change: 0
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.warning("Redo failed: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | redoing: false}}
    end
  end

  @impl true
  def handle_call(:stop_capturing, _from, state) do
    {:reply, :ok, %{state | last_change: 0}}
  end

  @impl true
  def handle_call({:clear, opts}, _from, state) do
    clear_undo = Keyword.get(opts, :undo, true)
    clear_redo = Keyword.get(opts, :redo, true)

    new_state =
      state
      |> then(fn s -> if clear_undo, do: %{s | undo_stack: []}, else: s end)
      |> then(fn s -> if clear_redo, do: %{s | redo_stack: []}, else: s end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:can_undo?, _from, state) do
    {:reply, length(state.undo_stack) > 0, state}
  end

  @impl true
  def handle_call(:can_redo?, _from, state) do
    {:reply, length(state.redo_stack) > 0, state}
  end

  @impl true
  def handle_call(:undo_stack_length, _from, state) do
    {:reply, length(state.undo_stack), state}
  end

  @impl true
  def handle_call(:redo_stack_length, _from, state) do
    {:reply, length(state.redo_stack), state}
  end

  @impl true
  def handle_info({:after_transaction, transaction}, state) do
    # Don't capture if we're currently undoing or redoing
    if state.undoing or state.redoing do
      {:noreply, state}
    else
      new_state = maybe_capture_transaction(transaction, state)
      {:noreply, new_state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp maybe_capture_transaction(transaction, state) do
    if should_track?(transaction, state) do
      capture_transaction(transaction, state)
    else
      state
    end
  end

  defp should_track?(transaction, state) do
    # Check if transaction origin is tracked
    origin_tracked =
      case state.tracked_origins do
        nil -> transaction.local
        origins -> MapSet.member?(origins, transaction.origin)
      end

    # Check if any tracked types were changed
    types_changed =
      Enum.any?(state.tracked_types, fn type_name ->
        MapSet.member?(transaction.changed, type_name)
      end)

    origin_tracked and types_changed
  end

  defp capture_transaction(transaction, state) do
    now = System.monotonic_time(:millisecond)

    # Get client_id from the doc
    {:ok, doc} = Doc.get_instance(state.doc_name)
    client_id = doc.client_id

    # Create stack item from transaction
    stack_item = StackItem.from_transaction(transaction, state.tracked_types, client_id)

    # Don't capture empty stack items
    if StackItem.empty?(stack_item) do
      state
    else
      # Check if we should merge with the last stack item
      # last_change == 0 means never set, so don't merge
      if state.capturing and state.last_change != 0 and
           (now - state.last_change) < state.capture_timeout and
           length(state.undo_stack) > 0 do
        # Merge with last stack item
        [last | rest] = state.undo_stack
        merged = StackItem.merge(last, stack_item)

        %{
          state
          | undo_stack: [merged | rest],
            redo_stack: [],
            last_change: now
        }
      else
        # Create new stack item
        %{
          state
          | undo_stack: [stack_item | state.undo_stack],
            redo_stack: [],
            last_change: now,
            capturing: true
        }
      end
    end
  end

  defp apply_undo(stack_item, state) do
    # For undo: delete what was inserted, restore what was deleted
    Doc.transact(state.doc_name, fn transaction ->
      # Delete inserted items
      transaction =
        Enum.reduce(stack_item.insertions, transaction, fn {client, items}, t ->
          Enum.reduce(items, t, fn {clock, len}, t ->
            mark_items_as_deleted(t, client, clock, len)
          end)
        end)

      # Restore deleted items
      transaction =
        Enum.reduce(stack_item.deletions, transaction, fn {client, items}, t ->
          Enum.reduce(items, t, fn {clock, len}, t ->
            restore_deleted_items(t, client, clock, len)
          end)
        end)

      {:ok, transaction}
    end, origin: :undo)

    # Create redo item - keep same structure (will be interpreted correctly by apply_redo)
    # insertions = items that need to be restored on redo
    # deletions = items that need to be deleted on redo
    redo_item = %StackItem{
      insertions: stack_item.insertions,
      deletions: stack_item.deletions,
      meta: stack_item.meta
    }

    {:ok, redo_item}
  end

  defp apply_redo(stack_item, state) do
    # For redo: restore items that were deleted during undo (insertions),
    # delete items that were restored during undo (deletions)
    Doc.transact(state.doc_name, fn transaction ->
      # Restore items that were deleted during undo (original insertions)
      transaction =
        Enum.reduce(stack_item.insertions, transaction, fn {client, items}, t ->
          Enum.reduce(items, t, fn {clock, len}, t ->
            restore_deleted_items(t, client, clock, len)
          end)
        end)

      # Delete items that were restored during undo (original deletions)
      transaction =
        Enum.reduce(stack_item.deletions, transaction, fn {client, items}, t ->
          Enum.reduce(items, t, fn {clock, len}, t ->
            mark_items_as_deleted(t, client, clock, len)
          end)
        end)

      {:ok, transaction}
    end, origin: :redo)

    # Create undo item - same structure for next undo
    undo_item = %StackItem{
      insertions: stack_item.insertions,
      deletions: stack_item.deletions,
      meta: stack_item.meta
    }

    {:ok, undo_item}
  end

  defp mark_items_as_deleted(transaction, client, clock, len) do
    # Find items in the clock range and mark them as deleted
    Enum.reduce(0..(len - 1), transaction, fn offset, t ->
      id = ID.new(client, clock + offset)

      case Doc.find_item(t, nil, id) do
        %Item{deleted?: false} = item ->
          deleted_item = Item.delete(item)
          update_item_in_doc(t, deleted_item)

        _ ->
          t
      end
    end)
  end

  defp restore_deleted_items(transaction, client, clock, len) do
    # Find deleted items in the clock range and restore them
    Enum.reduce(0..(len - 1), transaction, fn offset, t ->
      id = ID.new(client, clock + offset)

      case Doc.find_item(t, nil, id) do
        %Item{deleted?: true} = item ->
          # Restore (undelete)
          restored_item = %{item | deleted?: false}
          update_item_in_doc(t, restored_item)

        _ ->
          t
      end
    end)
  end

  defp update_item_in_doc(%Transaction{doc: doc} = transaction, %Item{} = item) do
    # Find the type containing this item and update it
    new_share =
      Enum.map(doc.share, fn {name, type} ->
        case Y.Type.find(type, item.id) do
          nil ->
            {name, type}

          found ->
            case Y.Type.unsafe_replace(type, found, [item]) do
              {:ok, new_type} -> {name, new_type}
              _ -> {name, type}
            end
        end
      end)
      |> Enum.into(%{})

    %{transaction | doc: %{doc | share: new_share}}
  end
end
