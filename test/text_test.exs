defmodule Y.TextTest do
  use ExUnit.Case
  alias Y.Doc
  alias Y.Type.Text

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

      {:ok, transaction}
    end)
  end
end
