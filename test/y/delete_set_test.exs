defmodule Y.DeleteSetTest do
  use ExUnit.Case

  alias Y.DeleteSet
  alias Y.DeleteSet.Item

  test "sort_and_merge_dels" do
    dels = [
      %Item{clock: 2, len: 2},
      %Item{clock: 4, len: 1},
      %Item{clock: 5, len: 1},
      %Item{clock: 7, len: 1},
      %Item{clock: 12, len: 1},
      %Item{clock: 14, len: 2},
      %Item{clock: 17, len: 2},
      %Item{clock: 23, len: 1},
      %Item{clock: 24, len: 1},
      %Item{clock: 25, len: 1},
      %Item{clock: 27, len: 1},
      %Item{clock: 32, len: 1},
      %Item{clock: 33, len: 1},
      %Item{clock: 35, len: 1},
      %Item{clock: 37, len: 1},
      %Item{clock: 42, len: 1},
      %Item{clock: 47, len: 1},
      %Item{clock: 52, len: 1},
      %Item{clock: 54, len: 1},
      %Item{clock: 55, len: 1},
      %Item{clock: 60, len: 1},
      %Item{clock: 62, len: 1},
      %Item{clock: 63, len: 2},
      %Item{clock: 69, len: 1},
      %Item{clock: 71, len: 4},
      %Item{clock: 79, len: 1},
      %Item{clock: 80, len: 1},
      %Item{clock: 81, len: 1},
      %Item{clock: 83, len: 1},
      %Item{clock: 84, len: 2},
      %Item{clock: 90, len: 1},
      %Item{clock: 91, len: 3},
      %Item{clock: 94, len: 1},
      %Item{clock: 95, len: 1},
      %Item{clock: 100, len: 1},
      %Item{clock: 105, len: 2},
      %Item{clock: 111, len: 3},
      %Item{clock: 114, len: 1},
      %Item{clock: 119, len: 1}
    ]

    assert [
             %Item{clock: 2, len: 4},
             %Item{clock: 7, len: 1},
             %Item{clock: 12, len: 1},
             %Item{clock: 14, len: 2},
             %Item{clock: 17, len: 2},
             %Item{clock: 23, len: 3},
             %Item{clock: 27, len: 1},
             %Item{clock: 32, len: 2},
             %Item{clock: 35, len: 1},
             %Item{clock: 37, len: 1},
             %Item{clock: 42, len: 1},
             %Item{clock: 47, len: 1},
             %Item{clock: 52, len: 1},
             %Item{clock: 54, len: 2},
             %Item{clock: 60, len: 1},
             %Item{clock: 62, len: 3},
             %Item{clock: 69, len: 1},
             %Item{clock: 71, len: 4},
             %Item{clock: 79, len: 3},
             %Item{clock: 83, len: 3},
             %Item{clock: 90, len: 6},
             %Item{clock: 100, len: 1},
             %Item{clock: 105, len: 2},
             %Item{clock: 111, len: 4},
             %Item{clock: 119, len: 1}
           ] = DeleteSet.sort_and_merge_dels({1, dels})

    dels2 = [
      %Item{clock: 156, len: 1},
      %Item{clock: 157, len: 1}
    ]

    [%Item{clock: 156, len: 2}] = DeleteSet.sort_and_merge_dels({2, dels2})

    dels3 = [%Item{clock: 0, len: 27}]
    assert [%Item{clock: 0, len: 27}] = DeleteSet.sort_and_merge_dels({3, dels3})
  end
end
