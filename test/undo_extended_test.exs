defmodule Y.UndoExtendedTest do
  @moduledoc """
  Extended UndoManager tests ported from Y.js tests/undo-extended.tests.js

  Tests:
  1. testMultipleUndoManagers - Two managers tracking different types independently
  2. testUndoDeepNestedTypes - Undo operations on Map inside Array inside Map
  3. testUndoFormatAfterConcurrentInsert - Remote insert while local format (SKIP - needs sync)
  4. testUndoManagerClearAndContinue - Clear stacks, then continue with new operations
  """
  use ExUnit.Case

  alias Y.Doc
  alias Y.Type.Text
  alias Y.Type.Array
  alias Y.UndoManager

  # ============================================================================
  # testMultipleUndoManagers
  # ============================================================================

  @doc """
  Test multiple undo managers on same document.
  Ported from Y.js testMultipleUndoManagers
  """
  test "multiple undo managers on same document" do
    {:ok, doc} = Doc.new(name: :undo_multiple_test)

    # Create undo managers tracking different types
    {:ok, text_undo_manager} = UndoManager.new(:undo_multiple_test, ["text"])
    {:ok, array_undo_manager} = UndoManager.new(:undo_multiple_test, ["array"])

    # Give GenServers time to subscribe
    Process.sleep(10)

    Doc.transact(doc, fn transaction ->
      {:ok, text, transaction} = Doc.get_text(transaction, "text")
      {:ok, array, transaction} = Doc.get_array(transaction, "array")

      {:ok, _text, transaction} = Text.insert(text, transaction, 0, "hello")
      {:ok, array, transaction} = Array.put(array, transaction, 0, 1)
      {:ok, array, transaction} = Array.put(array, transaction, 1, 2)
      {:ok, _array, transaction} = Array.put(array, transaction, 2, 3)

      {:ok, transaction}
    end)

    # Check initial state
    {:ok, doc} = Doc.get_instance(:undo_multiple_test)
    text = doc.share["text"]
    array = doc.share["array"]

    assert "hello" == Text.to_string(text)
    assert 3 == Array.length(array)

    # Undo only text changes
    UndoManager.undo(text_undo_manager)

    {:ok, doc} = Doc.get_instance(:undo_multiple_test)
    text = doc.share["text"]
    array = doc.share["array"]

    assert "" == Text.to_string(text)
    assert 3 == Array.length(array)

    # Undo array changes
    UndoManager.undo(array_undo_manager)

    {:ok, doc} = Doc.get_instance(:undo_multiple_test)
    array = doc.share["array"]

    assert 0 == Array.length(array)

    # Redo both
    UndoManager.redo(text_undo_manager)
    UndoManager.redo(array_undo_manager)

    {:ok, doc} = Doc.get_instance(:undo_multiple_test)
    text = doc.share["text"]
    array = doc.share["array"]

    assert "hello" == Text.to_string(text)
    assert 3 == Array.length(array)

    # Clean up
    GenServer.stop(text_undo_manager)
    GenServer.stop(array_undo_manager)
  end

  # ============================================================================
  # testUndoDeepNestedTypes
  # ============================================================================

  @tag :skip
  @doc """
  Test undo with deeply nested types.
  Ported from Y.js testUndoDeepNestedTypes

  In Y.js:
  ```javascript
  const ydoc = new Y.Doc()
  const root = ydoc.getMap('root')
  const undoManager = new Y.UndoManager(root)

  const items = new Y.Array()
  const item = new Y.Map()
  const data = new Y.Map()

  ydoc.transact(() => {
    root.set('items', items)
    items.insert(0, [item])
    item.set('data', data)
    data.set('value', 'initial')
  })

  // { items: [{ data: { value: 'initial' } }] }

  undoManager.stopCapturing()

  ydoc.transact(() => {
    data.set('value', 'modified')
  })

  // { items: [{ data: { value: 'modified' } }] }

  undoManager.undo()
  // { items: [{ data: { value: 'initial' } }] }
  ```

  Note: Requires UndoManager to recursively track changes in nested types.
  Currently, UndoManager only tracks direct children of tracked types.
  """
  test "undo with deeply nested types" do
    # This test requires UndoManager to recursively track nested types
    # which is a more complex feature to implement
    flunk("UndoManager doesn't track changes in nested types recursively")
  end

  # ============================================================================
  # testUndoFormatAfterConcurrentInsert
  # ============================================================================

  @tag :skip
  @doc """
  Test undo format after concurrent insert with tracked origins.
  Ported from Y.js testUndoFormatAfterConcurrentInsert

  Note: Requires UndoManager with trackedOrigins and multi-user sync.
  """
  test "undo format after concurrent insert" do
    flunk("Multi-user sync not implemented")
  end

  # ============================================================================
  # testUndoManagerClearAndContinue
  # ============================================================================

  @doc """
  Test undo manager clear and continue.
  Ported from Y.js testUndoManagerClearAndContinue
  """
  test "undo manager clear and continue" do
    {:ok, doc} = Doc.new(name: :undo_clear_test)

    {:ok, undo_manager} = UndoManager.new(:undo_clear_test, ["text"])

    # Give GenServer time to subscribe
    Process.sleep(10)

    # First insert
    Doc.transact(doc, fn transaction ->
      {:ok, text, transaction} = Doc.get_text(transaction, "text")
      {:ok, _text, transaction} = Text.insert(text, transaction, 0, "first")
      {:ok, transaction}
    end)

    # Wait for capture timeout to pass, then stop capturing
    Process.sleep(600)
    UndoManager.stop_capturing(undo_manager)

    # Second insert
    Doc.transact(doc, fn transaction ->
      text = transaction.doc.share["text"]
      {:ok, _text, transaction} = Text.insert(text, transaction, 5, " second")
      {:ok, transaction}
    end)

    # Wait for transaction to be captured
    Process.sleep(10)

    assert 2 == UndoManager.undo_stack_length(undo_manager)

    # Clear all stacks
    UndoManager.clear(undo_manager)

    assert 0 == UndoManager.undo_stack_length(undo_manager)
    assert 0 == UndoManager.redo_stack_length(undo_manager)

    # Continue with new operations
    Doc.transact(doc, fn transaction ->
      text = transaction.doc.share["text"]
      {:ok, _text, transaction} = Text.insert(text, transaction, 12, " third")
      {:ok, transaction}
    end)

    {:ok, doc} = Doc.get_instance(:undo_clear_test)
    text = doc.share["text"]
    assert "first second third" == Text.to_string(text)

    # Should be able to undo new operation
    UndoManager.undo(undo_manager)

    {:ok, doc} = Doc.get_instance(:undo_clear_test)
    text = doc.share["text"]
    assert "first second" == Text.to_string(text)

    # Cannot undo cleared operations
    UndoManager.undo(undo_manager)

    {:ok, doc} = Doc.get_instance(:undo_clear_test)
    text = doc.share["text"]
    assert "first second" == Text.to_string(text)

    # Clean up
    GenServer.stop(undo_manager)
  end
end
