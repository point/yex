defmodule Y.TextExtendedTest do
  @moduledoc """
  Extended text tests ported from Y.js tests/text-extended.tests.js

  Tests:
  1. testTextFormatOverlapping - Format overlapping ranges with bold and italic
  2. testTextInsertAtFormatBoundary - Insert at format boundary inherits format
  3. testTextDeleteAcrossFormats - Delete spanning multiple format ranges
  4. testTextConcurrentFormatting - Two users format same range (SKIP - needs multi-user sync)
  5. testTextFormatThenDeletePartial - Format then delete part of formatted range
  """
  use ExUnit.Case
  alias Y.Doc
  alias Y.Type.Text

  # ============================================================================
  # testTextFormatOverlapping
  # ============================================================================

  @doc """
  Test overlapping format ranges (bold AND italic)
  Ported from Y.js testTextFormatOverlapping

  In Y.js:
  ```javascript
  ytext.insert(0, 'hello world')
  ytext.format(0, 9, { bold: true })   // "hello wor" bold
  ytext.format(3, 8, { italic: true }) // "lo world" italic

  // Expected: "hel" bold, "lo wor" bold+italic, "ld" italic
  ```
  """
  test "text format overlapping" do
    {:ok, doc} = Doc.new(name: :text_format_overlapping)

    Doc.transact(doc, fn transaction ->
      {:ok, text, transaction} = Doc.get_text(transaction, "text")

      {:ok, text, transaction} = Text.insert(text, transaction, 0, "hello world")

      # Format "hello wor" (positions 0-8, length 9) with bold
      {:ok, text, transaction} = Text.format(text, transaction, 0, 9, %{bold: true})

      # Format "lo world" (positions 3-10, length 8) with italic
      {:ok, text, transaction} = Text.format(text, transaction, 3, 8, %{italic: true})

      assert "hello world" == Text.to_string(text)

      # Check the delta
      delta = Text.to_delta(text)

      # Expected:
      # "hel" bold only
      # "lo wor" bold+italic
      # "ld" italic only

      assert length(delta) == 3

      [first, second, third] = delta
      assert first.insert == "hel"
      assert first.attributes == %{bold: true}

      assert second.insert == "lo wor"
      assert second.attributes == %{bold: true, italic: true}

      assert third.insert == "ld"
      assert third.attributes == %{italic: true}

      {:ok, transaction}
    end)
  end

  # ============================================================================
  # testTextInsertAtFormatBoundary
  # ============================================================================

  @doc """
  Test insert exactly at format boundary
  Ported from Y.js testTextInsertAtFormatBoundary

  In Y.js:
  ```javascript
  ytext.insert(0, 'helloworld')
  ytext.format(0, 5, { bold: true }) // "hello" is bold
  ytext.insert(5, ' ')              // Insert at boundary

  // Space inherits bold because it's inserted at format boundary
  // Expected: "hello " bold, "world" plain
  ```
  """
  test "text insert at format boundary" do
    {:ok, doc} = Doc.new(name: :text_insert_boundary)

    Doc.transact(doc, fn transaction ->
      {:ok, text, transaction} = Doc.get_text(transaction, "text")

      {:ok, text, transaction} = Text.insert(text, transaction, 0, "helloworld")

      # Format "hello" (positions 0-4, length 5) with bold
      {:ok, text, transaction} = Text.format(text, transaction, 0, 5, %{bold: true})

      # Insert space at position 5 (at the format boundary)
      {:ok, text, transaction} = Text.insert(text, transaction, 5, " ")

      assert "hello world" == Text.to_string(text)

      # The space should inherit bold since it's inserted at the end of formatted region
      delta = Text.to_delta(text)

      # Expected: "hello " bold, "world" plain
      assert length(delta) == 2

      [first, second] = delta
      assert first.insert == "hello "
      assert first.attributes == %{bold: true}

      assert second.insert == "world"
      assert Map.get(second, :attributes) == nil

      {:ok, transaction}
    end)
  end

  # ============================================================================
  # testTextDeleteAcrossFormats
  # ============================================================================

  @doc """
  Test delete spanning multiple format ranges
  Ported from Y.js testTextDeleteAcrossFormats

  In Y.js:
  ```javascript
  ytext.insert(0, 'aaabbbccc')
  ytext.format(0, 3, { bold: true })      // "aaa" bold
  ytext.format(3, 3, { italic: true })    // "bbb" italic
  ytext.format(6, 3, { underline: true }) // "ccc" underline

  ytext.delete(2, 6) // Delete "abbbcc"

  // Expected: "aac" with "aa" bold, "c" underline
  ```
  """
  test "text delete across formats" do
    {:ok, doc} = Doc.new(name: :text_delete_across)

    Doc.transact(doc, fn transaction ->
      {:ok, text, transaction} = Doc.get_text(transaction, "text")

      {:ok, text, transaction} = Text.insert(text, transaction, 0, "aaabbbccc")

      # Format "aaa" with bold
      {:ok, text, transaction} = Text.format(text, transaction, 0, 3, %{bold: true})
      # Format "bbb" with italic
      {:ok, text, transaction} = Text.format(text, transaction, 3, 3, %{italic: true})
      # Format "ccc" with underline
      {:ok, text, transaction} = Text.format(text, transaction, 6, 3, %{underline: true})

      # Delete "abbbcc" (from position 2, length 6)
      {:ok, text, transaction} = Text.delete(text, transaction, 2, 6)

      assert "aac" == Text.to_string(text)

      # Check the delta
      delta = Text.to_delta(text)

      # Expected: "aa" bold, "c" underline
      assert length(delta) == 2

      [first, second] = delta
      assert first.insert == "aa"
      assert first.attributes == %{bold: true}

      assert second.insert == "c"
      assert second.attributes == %{underline: true}

      {:ok, transaction}
    end)
  end

  # ============================================================================
  # testTextConcurrentFormatting
  # ============================================================================

  @tag :skip
  @doc """
  Test concurrent formatting on same range
  Ported from Y.js testTextConcurrentFormatting

  In Y.js:
  ```javascript
  const { testConnector, users, text0, text1 } = init(tc, { users: 2 })

  text0.insert(0, 'hello')
  testConnector.flushAllMessages()

  // Both users format the same range with different attributes
  text0.format(0, 5, { bold: true })
  text1.format(0, 5, { italic: true })

  testConnector.flushAllMessages()

  // Both formats should be applied
  // Expected: "hello" with bold: true AND italic: true
  ```

  Note: Requires encoder/decoder support for Content.Format (content_ref 6) with key encoding.
  The V2 encoder needs a key clock encoder for format keys.
  """
  test "text concurrent formatting" do
    flunk("Encoder doesn't support Content.Format key encoding for sync")
  end

  # ============================================================================
  # testTextFormatThenDeletePartial
  # ============================================================================

  @doc """
  Test format then delete partial
  Ported from Y.js testTextFormatThenDeletePartial

  In Y.js:
  ```javascript
  ytext.insert(0, 'hello world')
  ytext.format(0, 11, { bold: true }) // All bold

  ytext.delete(3, 5) // Delete "lo wo"

  // Expected: "helrld" all bold
  ```
  """
  test "text format then delete partial" do
    {:ok, doc} = Doc.new(name: :text_format_delete)

    Doc.transact(doc, fn transaction ->
      {:ok, text, transaction} = Doc.get_text(transaction, "text")

      {:ok, text, transaction} = Text.insert(text, transaction, 0, "hello world")

      # Format all with bold
      {:ok, text, transaction} = Text.format(text, transaction, 0, 11, %{bold: true})

      # Delete "lo wo" (from position 3, length 5)
      {:ok, text, transaction} = Text.delete(text, transaction, 3, 5)

      assert "helrld" == Text.to_string(text)

      # Check the delta - should all be bold
      delta = Text.to_delta(text)

      assert length(delta) == 1
      [entry] = delta
      assert entry.insert == "helrld"
      assert entry.attributes == %{bold: true}

      {:ok, transaction}
    end)
  end
end
