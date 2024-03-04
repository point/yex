defmodule Y.ItemTest do
  use ExUnit.Case
  alias Y.Item

  test "explode" do
    item = %Y.Item{
      id: %Y.ID{client: 123, clock: 0},
      length: 6,
      content: [0, 1, 2, 3, 4, 5],
      origin: nil,
      right_origin: %Y.ID{client: 456, clock: 0},
      parent_name: "array_pack",
      parent_sub: nil,
      deleted?: false,
      keep?: true
    }

    assert [
             %Y.Item{
               id: %Y.ID{client: 123, clock: 0},
               length: 1,
               content: [0],
               origin: nil,
               right_origin: nil
             },
             %Y.Item{
               id: %Y.ID{client: 123, clock: 1},
               length: 1,
               content: [1],
               origin: %Y.ID{client: 123, clock: 0},
               right_origin: nil
             },
             %Y.Item{
               id: %Y.ID{client: 123, clock: 2},
               length: 1,
               content: [2],
               origin: %Y.ID{client: 123, clock: 1},
               right_origin: nil
             },
             %Y.Item{
               id: %Y.ID{client: 123, clock: 3},
               length: 1,
               content: [3],
               origin: %Y.ID{client: 123, clock: 2},
               right_origin: nil
             },
             %Y.Item{
               id: %Y.ID{client: 123, clock: 4},
               length: 1,
               content: [4],
               origin: %Y.ID{client: 123, clock: 3},
               right_origin: nil
             },
             %Y.Item{
               id: %Y.ID{client: 123, clock: 5},
               length: 1,
               content: [5],
               origin: %Y.ID{client: 123, clock: 4},
               right_origin: %Y.ID{client: 456, clock: 0}
             }
           ] = Item.explode(item)

    single = %Y.Item{
      id: %Y.ID{client: 123, clock: 0},
      length: 1,
      content: [0],
      origin: nil,
      right_origin: nil,
      parent_name: "array_pack",
      parent_sub: nil,
      deleted?: false,
      keep?: true
    }

    assert [^single] = Item.explode(single)

    double = %Y.Item{
      id: %Y.ID{client: 123, clock: 0},
      length: 2,
      content: [0, 1],
      origin: nil,
      right_origin: nil,
      parent_name: "array_pack",
      parent_sub: nil,
      deleted?: false,
      keep?: true
    }

    assert [
             %Y.Item{
               id: %Y.ID{client: 123, clock: 0},
               length: 1,
               content: [0]
             },
             %Y.Item{
               id: %Y.ID{client: 123, clock: 1},
               length: 1,
               content: [1],
               origin: %Y.ID{client: 123, clock: 0},
               right_origin: nil
             }
           ] = Item.explode(double)
  end
end
