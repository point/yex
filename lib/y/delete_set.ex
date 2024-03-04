defmodule Y.DeleteSet do
  defmodule Item do
    defstruct clock: 0, len: 0
  end

  # def sort_and_merge_delete_set(%Store{clients: clients} = store) do
  #   %{store | clients: Enum.map(clients, &sort_and_merge_dels/1)}
  # end

  def sort_and_merge_dels({_number, dels}) do
    # i is the current pointer
    # j refers to the current insert position for the pointed item
    # try to merge dels[i] into dels[j-1] or set dels[j]=dels[i]

    loop = fn
      loop, i, j, acc ->
        left = Enum.at(acc, j - 1) || Enum.at(dels, j - 1)
        right = Enum.at(dels, i)

        if left.clock + left.len >= right.clock do
          acc =
            maybe_insert(acc, j - 1, left, fn e ->
              %{e | len: max(e.len, right.clock + right.len - e.clock)}
            end)

          if i < length(dels) - 1, do: loop.(loop, i + 1, j, acc), else: acc
        else
          acc = if j < i, do: maybe_insert(acc, j, right, fn _ -> right end)
          if i < length(dels) - 1, do: loop.(loop, i + 1, j + 1, acc), else: acc
        end
    end

    case Enum.sort(dels, &(&1.clock <= &2.clock)) do
      [] -> []
      [_] = d -> d
      _ -> loop.(loop, 1, 1, [])
    end
  end

  defp maybe_insert(acc, pos, if_not_exists, fun) do
    case Enum.at(acc, pos) do
      nil -> List.insert_at(acc, pos, fun.(if_not_exists))
      e -> List.replace_at(acc, pos, fun.(e))
    end
  end
end
