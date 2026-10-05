defmodule Crit.LineDiff do
  @moduledoc false

  # Line diff used to carry comments onto a new file version. This is
  # Hirschberg's LCS, matching crit's internal/diff.ComputeLineDiff and
  # MapOldLineToNew so a comment moves with the same line crit would choose.

  def split_lines(""), do: []
  def split_lines(content) when is_binary(content), do: String.split(content, "\n")

  def compute(old_content, new_content) do
    hirschberg(split_lines(old_content), split_lines(new_content), 0, 0)
  end

  def map_old_to_new(entries) do
    direct =
      for %{type: "unchanged", old_line: old, new_line: new} <- entries,
          into: %{},
          do: {old, new}

    {mapped, next_new_line} =
      Enum.reduce(Enum.reverse(entries), {direct, 0}, fn entry, {mapped, next_new_line} ->
        next_new_line = if entry.new_line > 0, do: entry.new_line, else: next_new_line

        mapped =
          if entry.type == "removed" and not Map.has_key?(mapped, entry.old_line) do
            Map.put(mapped, entry.old_line, next_new_line)
          else
            mapped
          end

        {mapped, next_new_line}
      end)

    if next_new_line == 0 do
      last_new_line =
        Enum.reduce(entries, 0, fn entry, last ->
          if entry.new_line > 0, do: entry.new_line, else: last
        end)

      if last_new_line > 0 do
        Enum.reduce(entries, mapped, fn
          %{type: "removed", old_line: old}, acc ->
            if Map.get(acc, old) == 0, do: Map.put(acc, old, last_new_line), else: acc

          _, acc ->
            acc
        end)
      else
        mapped
      end
    else
      mapped
    end
  end

  defp hirschberg([], new, _old_off, new_off), do: all_added(new, new_off)
  defp hirschberg(old, [], old_off, _new_off), do: all_removed(old, old_off)
  defp hirschberg([only], new, old_off, new_off), do: diff_single_old(only, new, old_off, new_off)

  defp hirschberg(old, new, old_off, new_off) do
    mid = div(length(old), 2)
    {left_old, right_old} = Enum.split(old, mid)
    n = length(new)
    best_k = best_split(lcs_forward_row(left_old, new), lcs_backward_row(right_old, new), n)
    {left_new, right_new} = Enum.split(new, best_k)

    hirschberg(left_old, left_new, old_off, new_off) ++
      hirschberg(right_old, right_new, old_off + mid, new_off + best_k)
  end

  defp diff_single_old(old_line, new, old_off, new_off) do
    case Enum.find_index(new, &(&1 == old_line)) do
      nil ->
        [%{type: "removed", old_line: old_off + 1, new_line: 0, text: old_line}] ++
          all_added(new, new_off)

      match_idx ->
        {before, [_ | after_]} = Enum.split(new, match_idx)

        all_added(before, new_off) ++
          [
            %{
              type: "unchanged",
              old_line: old_off + 1,
              new_line: new_off + match_idx + 1,
              text: old_line
            }
          ] ++ all_added(after_, new_off + match_idx + 1)
    end
  end

  defp all_added(lines, offset) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      %{type: "added", old_line: 0, new_line: offset + i + 1, text: line}
    end)
  end

  defp all_removed(lines, offset) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      %{type: "removed", old_line: offset + i + 1, new_line: 0, text: line}
    end)
  end

  defp best_split(top, bot, n) do
    Enum.reduce(0..n, {0, :array.get(0, top) + :array.get(n, bot)}, fn k, {best_k, best_score} ->
      score = :array.get(k, top) + :array.get(n - k, bot)
      if score > best_score, do: {k, score}, else: {best_k, best_score}
    end)
    |> elem(0)
  end

  defp lcs_forward_row(old, new) do
    n = length(new)
    new_t = List.to_tuple(new)

    Enum.reduce(old, zeros(n + 1), fn old_line, prev ->
      Enum.reduce(1..n, zeros(n + 1), fn j, curr ->
        value =
          cond do
            old_line == elem(new_t, j - 1) ->
              :array.get(j - 1, prev) + 1

            :array.get(j, prev) >= :array.get(j - 1, curr) ->
              :array.get(j, prev)

            true ->
              :array.get(j - 1, curr)
          end

        :array.set(j, value, curr)
      end)
    end)
  end

  defp lcs_backward_row(old, new) do
    n = length(new)
    old_t = List.to_tuple(old)
    new_t = List.to_tuple(new)

    if old == [] do
      zeros(n + 1)
    else
      Enum.reduce((length(old) - 1)..0//-1, zeros(n + 1), fn i, prev ->
        Enum.reduce((n - 1)..0//-1, zeros(n + 1), fn j, curr ->
          idx = n - j

          value =
            cond do
              elem(old_t, i) == elem(new_t, j) ->
                :array.get(idx - 1, prev) + 1

              :array.get(idx, prev) >= :array.get(idx - 1, curr) ->
                :array.get(idx, prev)

              true ->
                :array.get(idx - 1, curr)
            end

          :array.set(idx, value, curr)
        end)
      end)
    end
  end

  defp zeros(size), do: :array.new(size, default: 0)
end
