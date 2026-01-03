defmodule Y.TextTest do
  use ExUnit.Case
  alias Y.Doc
  alias Y.Type.Text
  alias Y.Transaction

  test "insert" do
    {:ok, doc} = Doc.new(name: :text_insert)
    {:ok, _text} = Doc.get_text(doc, "text")

    Doc.transact(doc, fn transaction ->
      {:ok, text} = Doc.get(transaction, "text")
      {:ok, text, transaction} = Text.insert(text, transaction, 0, "abc", %{bold: true})

      assert [
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 1},
                 length: 1,
                 content: ["a"],
                 origin: %Y.ID{clock: 0},
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 2},
                 length: 1,
                 content: ["b"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 3},
                 length: 1,
                 content: ["c"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 origin: %Y.ID{clock: 3},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               }
             ] = Text.to_list(text, as_items: true, with_deleted: true)

      {:ok, text2, transaction} = Text.insert(text, transaction, 0, "d", %{em: true})

      assert [
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :em, value: true}],
                 origin: nil,
                 right_origin: %Y.ID{clock: 0},
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 5},
                 length: 1,
                 content: ["d"],
                 origin: %Y.ID{clock: 4},
                 right_origin: %Y.ID{clock: 0},
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 6},
                 length: 1,
                 content: [%Y.Content.Format{key: :em, value: nil}],
                 origin: %Y.ID{clock: 5},
                 right_origin: %Y.ID{clock: 0},
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 origin: nil,
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 1},
                 length: 1,
                 content: ["a"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 2},
                 length: 1,
                 content: ["b"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 3},
                 length: 1,
                 content: ["c"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 origin: %Y.ID{clock: 3},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               }
             ] = Text.to_list(text2, as_items: true, with_deleted: true)

      {:ok, text3, transaction} = Text.insert(text, transaction, 0, "d", %{em: true, bold: true})

      assert [
               %Y.Content.Format{key: :bold, value: true},
               %Y.Content.Format{key: :em, value: true},
               "d",
               %Y.Content.Format{key: :em, value: nil},
               "a",
               "b",
               "c",
               %Y.Content.Format{key: :bold, value: nil}
             ] = Text.to_list(text3, with_deleted: true)

      {:ok, text4, transaction} = Text.insert(text, transaction, 1, "d", %{em: true})

      assert [
               %Y.Content.Format{key: :bold, value: true},
               "a",
               %Y.Content.Format{key: :bold, value: nil},
               %Y.Content.Format{key: :em, value: true},
               "d",
               %Y.Content.Format{key: :bold, value: true},
               %Y.Content.Format{key: :em, value: nil},
               "b",
               "c",
               %Y.Content.Format{key: :bold, value: nil}
             ] = Text.to_list(text4, with_deleted: true)

      assert "adbc" = Text.to_string(text4)

      {:ok, text5, transaction} =
        Text.insert(text, transaction, 0, "Test\nMulti-line\nFormatting")

      assert [
               "T",
               "e",
               "s",
               "t",
               "\n",
               "M",
               "u",
               "l",
               "t",
               "i",
               "-",
               "l",
               "i",
               "n",
               "e",
               "\n",
               "F",
               "o",
               "r",
               "m",
               "a",
               "t",
               "t",
               "i",
               "n",
               "g",
               %Y.Content.Format{key: :bold, value: true},
               "a",
               "b",
               "c",
               %Y.Content.Format{key: :bold, value: nil}
             ] = Text.to_list(text5, with_deleted: true)

      assert "Test\nMulti-line\nFormattingabc" = Text.to_string(text5)

      {:ok, text6, transaction} =
        Text.insert(text, transaction, 10, "e")

      assert [
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 origin: nil,
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 1},
                 length: 1,
                 content: ["a"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 2},
                 length: 1,
                 content: ["b"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 3},
                 length: 1,
                 content: ["c"],
                 origin: %Y.ID{clock: 0},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 origin: %Y.ID{clock: 3},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 38},
                 length: 1,
                 content: ["e"],
                 origin: %Y.ID{clock: 4},
                 right_origin: nil,
                 parent_name: "text",
                 deleted?: false
               }
             ] = Text.to_list(text6, as_items: true)

      # bold in bold
      {:ok, text7, transaction} =
        Text.insert(text, transaction, 1, "d", %{bold: true})

      assert [
               %Y.Content.Format{key: :bold, value: true},
               "a",
               "d",
               "b",
               "c",
               %Y.Content.Format{key: :bold, value: nil}
             ] = Text.to_list(text7)

      {:ok, transaction}
    end)
  end

  test "delete" do
    {:ok, doc} = Doc.new(name: :text_delete)
    {:ok, _text} = Doc.get_text(doc, "text")
    {:ok, _text} = Doc.get_text(doc, "text2")

    Doc.transact(doc, fn transaction ->
      {:ok, text} = Doc.get(transaction, "text")
      {:ok, text, transaction} = Text.insert(text, transaction, 0, "abc", %{bold: true})
      {:ok, text2, transaction} = Text.delete(text, transaction, 0, 2)

      assert [
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 1},
                 length: 1,
                 content: ["a"],
                 deleted?: true
               },
               %Y.Item{
                 id: %Y.ID{clock: 2},
                 length: 1,
                 content: ["b"],
                 deleted?: true
               },
               %Y.Item{
                 id: %Y.ID{clock: 3},
                 length: 1,
                 content: ["c"],
                 deleted?: false
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 deleted?: false
               }
             ] = Text.to_list(text2, as_items: true, with_deleted: true)

      {:ok, transaction}
    end)

    Doc.transact(doc, fn transaction ->
      {:ok, text} = Doc.get(transaction, "text2")
      {:ok, text, transaction} = Text.insert(text, transaction, 0, "a")
      {:ok, text, transaction} = Text.insert(text, transaction, 1, "bcd", %{bold: true})
      {:ok, text, transaction} = Text.delete(text, transaction, 0, 2)

      assert [
               %Y.Item{
                 content: ["a"],
                 deleted?: true,
                 id: %Y.ID{clock: 4},
                 length: 1,
                 keep?: true,
                 origin: nil,
                 right_origin: nil
               },
               %Y.Item{
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 deleted?: false,
                 id: %Y.ID{clock: 5},
                 length: 1,
                 keep?: true,
                 origin: %Y.ID{clock: 4},
                 right_origin: nil
               },
               %Y.Item{
                 content: ["b"],
                 deleted?: true,
                 id: %Y.ID{clock: 6},
                 length: 1,
                 keep?: true,
                 origin: %Y.ID{clock: 5},
                 right_origin: nil
               },
               %Y.Item{
                 content: ["c"],
                 deleted?: false,
                 id: %Y.ID{clock: 7},
                 length: 1,
                 keep?: true,
                 origin: %Y.ID{clock: 5},
                 right_origin: nil
               },
               %Y.Item{
                 content: ["d"],
                 deleted?: false,
                 id: %Y.ID{clock: 8},
                 length: 1,
                 keep?: true,
                 origin: %Y.ID{clock: 5},
                 right_origin: nil
               },
               %Y.Item{
                 id: %Y.ID{clock: 9},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 origin: %Y.ID{clock: 8},
                 right_origin: nil,
                 deleted?: false,
                 keep?: true
               }
             ] = Text.to_list(text, as_items: true, with_deleted: true)

      {:ok, transaction}
    end)
  end

  test "delete by index" do
    {:ok, doc} = Doc.new(name: :text_delete_by_index)
    {:ok, _text} = Doc.get_text(doc, "text")

    Doc.transact(doc, fn transaction ->
      {:ok, text} = Doc.get(transaction, "text")
      {:ok, text, transaction} = Text.insert(text, transaction, 0, "abc", %{bold: true})

      [format_begin | [l1 | [l2 | _]]] = Text.to_list(text, as_items: true, with_deleted: true)

      {:ok, text_1, transaction} = Text.delete_by_id(text, transaction, format_begin.id)
      assert [
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 origin: nil,
                 right_origin: nil,
                 parent_name: "text",
                 parent_sub: nil,
                 deleted?: false,
                 keep?: true
               },
               %Y.Item{
                 length: 1,
                 content: ["a"],
                 deleted?: true,
               },
               %Y.Item{
                 deleted?: false,
               },
               %Y.Item{
                 deleted?: false,
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 deleted?: false,
               }
             ] = Text.to_list(text_1, as_items: true, with_deleted: true)

      {:ok, text_2, transaction} = Text.delete_by_id(text, transaction, l1.id)

      assert [
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 deleted?: false,
               },
               %Y.Item{
                 length: 1,
                 content: ["a"],
                 deleted?: true,
               },
               %Y.Item{
                 deleted?: false,
               },
               %Y.Item{
                 deleted?: false,
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 deleted?: false,
               }
             ] = Text.to_list(text_2, as_items: true, with_deleted: true)

      {:ok, text_3, transaction} = Text.delete_by_id(text, transaction, l2.id)

      assert [
               %Y.Item{
                 id: %Y.ID{clock: 0},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: true}],
                 deleted?: false,
               },
               %Y.Item{
                 deleted?: false,
               },
               %Y.Item{
                 content: ["b"],
                 deleted?: true,
                 length: 1
               },
               %Y.Item{
                 deleted?: false,
               },
               %Y.Item{
                 id: %Y.ID{clock: 4},
                 length: 1,
                 content: [%Y.Content.Format{key: :bold, value: nil}],
                 deleted?: false,
               }
             ] = Text.to_list(text_3, as_items: true, with_deleted: true)


      assert {:error, _, _} = Text.delete_by_id(text, transaction, %{l2.id | clock: 100})

      {:ok, transaction}
    end)
  end

  test "pack" do
    {:ok, doc} = Doc.new(name: :text_pack)
    {:ok, _text} = Doc.get_text(doc, "text")

    Doc.transact(doc, fn transaction ->
      {:ok, text} = Doc.get(transaction, "text")
      {:ok, text, transaction} = Text.insert(text, transaction, 0, "abcd", %{bold: true})
      {:ok, _text, transaction} = Text.delete(text, transaction, 0, 2)

      {:ok, Transaction.force_pack(transaction)}
    end)

    {:ok, packed_text} = Doc.get(doc, "text")

    assert [
             %Y.Item{
               content: [%Y.Content.Format{key: :bold, value: true}],
               deleted?: false
             },
             %Y.Item{
               content: [%Y.Content.Deleted{len: 2}],
               deleted?: true
             },
             %Y.Item{
               content: %Y.Content.String{str: "cd"},
               deleted?: false
             },
             %Y.Item{
               content: [%Y.Content.Format{key: :bold, value: nil}],
               deleted?: false
             }
           ] = Text.to_list(packed_text, as_items: true, with_deleted: true)
  end
end
