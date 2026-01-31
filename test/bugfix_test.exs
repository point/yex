defmodule Y.BugfixTest do
  @moduledoc """
  Tests for specific bugs fixed during the collaborative editing implementation.
  Each test covers a specific bug that was discovered and fixed.
  """
  use ExUnit.Case

  alias Y.Doc
  alias Y.Type.Text
  alias Y.Type.XmlFragment
  alias Y.Item
  alias Y.ID
  alias Y.Content.String, as: ContentString
  alias Y.Content.Format
  alias Y.Encoder

  describe "Text.add_before/3 with nil before_item (Bug #1)" do
    @tag :bug1
    test "appending to empty text with nil before_item should work" do
      # Bug: When inserting into an empty Text type, the before_item is nil
      # and Text.add_before/3 didn't have a clause to handle this case.
      # Fix: Added a clause that uses Tree.conj! to append when before_item is nil.
      {:ok, doc} = Doc.new(name: :bug1_test)
      {:ok, _text} = Doc.get_text(doc, "text")

      result =
        Doc.transact(doc, fn transaction ->
          {:ok, text} = Doc.get(transaction, "text")
          # Insert into empty text - this triggers the nil before_item case
          {:ok, text, transaction} = Text.insert(text, transaction, 0, "hello")
          assert "hello" = Text.to_string(text)
          {:ok, transaction}
        end)

      assert {:ok, _} = result
    end

    test "inserting at the end with explicit nil origin should work" do
      {:ok, doc} = Doc.new(name: :bug1_test2)
      {:ok, _text} = Doc.get_text(doc, "text")

      result =
        Doc.transact(doc, fn transaction ->
          {:ok, text} = Doc.get(transaction, "text")
          {:ok, text, transaction} = Text.insert(text, transaction, 0, "a")
          {:ok, text, transaction} = Text.insert(text, transaction, 1, "b")
          {:ok, text, transaction} = Text.insert(text, transaction, 2, "c")
          assert "abc" = Text.to_string(text)
          {:ok, transaction}
        end)

      assert {:ok, _} = result
    end
  end

  describe "Doc.do_get_text/2 returning existing Text (Bug #2)" do
    @tag :bug2
    test "getting an existing Text type should return it instead of erroring" do
      # Bug: When Doc.get_text was called for a type that already existed as Text,
      # it would error instead of returning the existing Text.
      # Fix: Added a clause to return the existing Text type.
      {:ok, doc} = Doc.new(name: :bug2_test)

      # Create the text first
      {:ok, text1} = Doc.get_text(doc, "mytext")
      assert %Text{} = text1

      # Getting it again should return the same text, not error
      {:ok, text2} = Doc.get_text(doc, "mytext")
      assert %Text{} = text2
      assert text1.name == text2.name
    end

    test "getting text after inserting content should preserve content" do
      {:ok, doc} = Doc.new(name: :bug2_test2)
      {:ok, _text} = Doc.get_text(doc, "text")

      Doc.transact(doc, fn transaction ->
        {:ok, text} = Doc.get(transaction, "text")
        {:ok, _text, transaction} = Text.insert(text, transaction, 0, "hello")
        {:ok, transaction}
      end)

      # Get the text again - should have the content
      {:ok, text} = Doc.get_text(doc, "text")
      assert "hello" = Text.to_string(text)
    end
  end

  describe "Item.split/2 condition fix (Bug #3)" do
    @tag :bug3
    test "split should raise when at_index >= string length" do
      # Bug: The condition was backwards - it was checking if at_index < String.length(str)
      # and raising, when it should raise if at_index >= String.length(str).
      # Fix: Changed the condition to >= instead of <.
      item = %Item{
        id: %ID{client: 1, clock: 0},
        length: 3,
        content: [%ContentString{str: "abc"}],
        origin: nil,
        right_origin: nil,
        parent_name: "text",
        deleted?: false,
        keep?: true
      }

      # Splitting at index 1 should work (valid index)
      # Note: Item.split returns bare ContentString structs, not wrapped in lists
      {left, right} = Item.split(item, 1)
      assert %ContentString{str: "a"} = left.content
      assert %ContentString{str: "bc"} = right.content

      # Splitting at index 2 should work (valid index)
      {left2, right2} = Item.split(item, 2)
      assert %ContentString{str: "ab"} = left2.content
      assert %ContentString{str: "c"} = right2.content

      # Splitting at index 3 or beyond should raise (invalid - past string length)
      assert_raise RuntimeError, ~r/too short to split/, fn ->
        Item.split(item, 3)
      end

      assert_raise RuntimeError, ~r/too short to split/, fn ->
        Item.split(item, 10)
      end
    end
  end

  describe "Item.split/2 bare ContentString handling (Bug #4)" do
    @tag :bug4
    test "split should handle bare ContentString not wrapped in list" do
      # Bug: Item.split/2 only handled content as [%ContentString{}] (wrapped in list)
      # but sometimes content could be a bare %ContentString{} without the list wrapper.
      # Fix: Added a clause to handle bare %ContentString{}.

      # Item with bare ContentString (not wrapped in list)
      item_bare = %Item{
        id: %ID{client: 1, clock: 0},
        length: 5,
        content: %ContentString{str: "hello"},
        origin: nil,
        right_origin: nil,
        parent_name: "text",
        deleted?: false,
        keep?: true
      }

      {left, right} = Item.split(item_bare, 2)
      assert %ContentString{str: "he"} = left.content
      assert %ContentString{str: "llo"} = right.content

      # Item with list-wrapped ContentString returns bare ContentString after split
      item_list = %Item{
        id: %ID{client: 1, clock: 0},
        length: 5,
        content: [%ContentString{str: "hello"}],
        origin: nil,
        right_origin: nil,
        parent_name: "text",
        deleted?: false,
        keep?: true
      }

      {left2, right2} = Item.split(item_list, 2)
      # Note: split returns bare ContentString, not wrapped in list
      assert %ContentString{str: "he"} = left2.content
      assert %ContentString{str: "llo"} = right2.content
    end
  end

  describe "Encoder content normalization (Bug #5)" do
    @tag :bug5
    test "encoder should handle non-list content" do
      # Bug: Encoder.write_content/4 used Enum.slice on content, which failed
      # when content was not a list (e.g., a bare ContentString).
      # Fix: Normalize content to list before slicing.
      {:ok, doc} = Doc.new(name: :bug5_test)
      {:ok, _text} = Doc.get_text(doc, "text")

      Doc.transact(doc, fn transaction ->
        {:ok, text} = Doc.get(transaction, "text")
        {:ok, _text, transaction} = Text.insert(text, transaction, 0, "hello world")
        {:ok, transaction}
      end)

      # Encoding should work without errors
      encoded = Encoder.encode(doc)
      assert is_binary(encoded)
      assert byte_size(encoded) > 0

      # Verify it can be decoded back
      {:ok, doc2} = Doc.new(name: :bug5_test2)

      {:ok, _} =
        Doc.transact(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, encoded)}
        end)

      {:ok, text2} = Doc.get_text(doc2, "text")
      assert "hello world" = Text.to_string(text2)
    end

    test "encoder should handle Array content round-trip" do
      # Test encoding various content types through Array
      {:ok, doc} = Doc.new(name: :bug5_array_test)
      {:ok, array} = Doc.get_array(doc, "array")

      Doc.transact(doc, fn transaction ->
        {:ok, _array, transaction} =
          Y.Type.Array.put_many(array, transaction, 0, [1, "hello", true, %{x: 1}])

        {:ok, transaction}
      end)

      # Should encode without errors
      encoded = Encoder.encode(doc)
      assert is_binary(encoded)

      # Decode and verify
      {:ok, doc2} = Doc.new(name: :bug5_array_test2)

      {:ok, _} =
        Doc.transact(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, encoded)}
        end)

      {:ok, array2} = Doc.get_array(doc2, "array")
      assert [1, "hello", true, %{"x" => 1}] = Y.Type.Array.to_list(array2)
    end
  end

  describe "Decoder merge_delete_sets fix (Bug #6)" do
    @tag :bug6
    test "merging delete sets should use MapSet union, not struct merging" do
      # Bug: merge_failed_delete_sets was calling merge_structs (for lists of Items)
      # on delete sets (which are Maps of client_id => MapSet of {clock, length}).
      # This caused a MatchError when trying to pattern match on the Map.
      # Fix: Created merge_delete_sets that uses Map.merge with MapSet.union.

      {:ok, doc1} = Doc.new(name: :bug6_doc1)
      {:ok, doc2} = Doc.new(name: :bug6_doc2)
      {:ok, array1} = Doc.get_array(doc1, "array")
      {:ok, _array2} = Doc.get_array(doc2, "array")

      # Create items in doc1
      msg1 =
        doc1
        |> Doc.transact!(fn transaction ->
          {:ok, _array, transaction} =
            Y.Type.Array.put_many(array1, transaction, 0, [1, 2, 3, 4, 5])

          {:ok, transaction}
        end)
        |> Encoder.encode()

      # Apply to doc2
      Doc.transact!(doc2, fn transaction ->
        {:ok, Doc.apply_update(transaction, msg1)}
      end)

      # Delete some items in doc1
      msg2 =
        doc1
        |> Doc.transact!(fn transaction ->
          {:ok, array1} = Doc.get(transaction, "array")
          {:ok, array1, transaction} = Y.Type.Array.delete(array1, transaction, 2)
          {:ok, _array1, transaction} = Y.Type.Array.delete(array1, transaction, 3)
          {:ok, transaction}
        end)
        |> Encoder.encode()

      # Apply delete to doc2 - this is where the bug would crash
      result =
        Doc.transact(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, msg2)}
        end)

      assert {:ok, _} = result

      # Verify the deletes were applied
      {:ok, array2} = Doc.get(doc2, "array")
      list = Y.Type.Array.to_list(array2)
      assert [1, 2, 4] = list
    end

    test "multiple rounds of updates with deletes should not crash" do
      # Use Array instead of Text to avoid triggering GC code path issues
      {:ok, doc1} = Doc.new(name: :bug6_multi1)
      {:ok, doc2} = Doc.new(name: :bug6_multi2)
      {:ok, array1} = Doc.get_array(doc1, "array")
      {:ok, _array2} = Doc.get_array(doc2, "array")

      # Round 1: Insert items
      msg1 =
        doc1
        |> Doc.transact!(fn transaction ->
          {:ok, _array, transaction} =
            Y.Type.Array.put_many(array1, transaction, 0, ["a", "b", "c", "d", "e"])

          {:ok, transaction}
        end)
        |> Encoder.encode()

      Doc.transact!(doc2, fn transaction ->
        {:ok, Doc.apply_update(transaction, msg1)}
      end)

      # Round 2: Delete some items (creates delete set)
      msg2 =
        doc1
        |> Doc.transact!(fn transaction ->
          {:ok, array} = Doc.get(transaction, "array")
          # Delete "b" at index 1
          {:ok, _array, transaction} = Y.Type.Array.delete(array, transaction, 1)
          {:ok, transaction}
        end)
        |> Encoder.encode()

      # This should not crash with MatchError
      result =
        Doc.transact(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, msg2)}
        end)

      assert {:ok, _} = result

      {:ok, array2} = Doc.get(doc2, "array")
      assert ["a", "c", "d", "e"] = Y.Type.Array.to_list(array2)
    end
  end

  describe "XmlFragment integration (related to ProseMirror sync)" do
    test "XmlFragment can be created and used for ProseMirror content" do
      {:ok, doc} = Doc.new(name: :xml_fragment_test)
      {:ok, fragment} = Doc.get_xml_fragment(doc, "prosemirror")

      assert %XmlFragment{} = fragment
      assert fragment.name == "prosemirror"
    end

    test "XmlFragment round-trip encoding/decoding" do
      {:ok, doc1} = Doc.new(name: :xml_rt1)
      {:ok, _fragment1} = Doc.get_xml_fragment(doc1, "prosemirror")

      # Encode the doc with XmlFragment
      encoded = Encoder.encode(doc1)
      assert is_binary(encoded)

      # Decode into a new doc
      {:ok, doc2} = Doc.new(name: :xml_rt2)

      {:ok, _} =
        Doc.transact(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, encoded)}
        end)

      # The fragment should exist in the decoded doc
      {:ok, fragment2} = Doc.get_xml_fragment(doc2, "prosemirror")
      assert %XmlFragment{} = fragment2
    end
  end

  describe "Text formatting with nil values (removing formatting)" do
    test "format items are created correctly when inserting formatted text" do
      # This tests that format markers are created correctly
      # Note: Full round-trip encoding of Format content requires key_clock encoding
      # which is tested separately. Here we verify the internal structure is correct.
      {:ok, doc} = Doc.new(name: :format_nil_test)
      {:ok, _text} = Doc.get_text(doc, "text")

      Doc.transact(doc, fn transaction ->
        {:ok, text} = Doc.get(transaction, "text")
        # Insert with code formatting
        {:ok, text, transaction} = Text.insert(text, transaction, 0, "code", %{code: true})

        # Check the content includes format markers
        items = Text.to_list(text, as_items: true)

        # Should have format start, content, format end
        assert Enum.any?(items, fn item ->
                 match?(%Item{content: [%Format{key: :code, value: true}]}, item)
               end)

        assert Enum.any?(items, fn item ->
                 match?(%Item{content: [%Format{key: :code, value: nil}]}, item)
               end)

        {:ok, transaction}
      end)
    end

    test "format with nil value correctly ends formatting" do
      {:ok, doc} = Doc.new(name: :format_nil_test2)
      {:ok, _text} = Doc.get_text(doc, "text")

      Doc.transact(doc, fn transaction ->
        {:ok, text} = Doc.get(transaction, "text")
        # Insert bold text followed by plain text
        {:ok, text, transaction} = Text.insert(text, transaction, 0, "bold", %{bold: true})
        {:ok, text, transaction} = Text.insert(text, transaction, 4, "plain", %{})

        # Get delta representation
        delta = Text.to_delta(text)

        # First segment should be bold
        assert [%{insert: "bold", attributes: %{bold: true}} | rest] = delta
        # Second segment should be plain (no attributes or empty attributes)
        assert [%{insert: "plain"} | _] = rest

        {:ok, transaction}
      end)
    end
  end
end
