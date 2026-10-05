defmodule Crit.CommentCarryForward do
  @moduledoc false

  # Move a line comment from one file version to the next the way crit does
  # on a new review round: LCS line mapping, then check the anchor text.
  # A light in-place edit stays put. Text that moved is followed. Text that
  # is gone stays on the mapped line and is marked drifted.

  alias Crit.LineDiff

  def extract_anchor(content, start_line, end_line)
      when not is_integer(start_line) or not is_integer(end_line) or start_line <= 0 or
             end_line < start_line or content in [nil, ""] do
    ""
  end

  def extract_anchor(content, start_line, end_line) do
    lines = LineDiff.split_lines(content)

    if start_line > length(lines) do
      ""
    else
      finish = min(end_line, length(lines))
      lines |> Enum.slice((start_line - 1)..(finish - 1)) |> Enum.join("\n")
    end
  end

  def place(old_content, new_content, start_line, end_line, anchor) do
    new_lines = LineDiff.split_lines(new_content || "")
    line_map = old_content |> LineDiff.compute(new_content || "") |> LineDiff.map_old_to_new()
    max_line = max(length(new_lines), 1)
    {lcs_start, lcs_end} = remap_lines(line_map, start_line, end_line, max_line)

    if is_binary(anchor) and anchor != "" do
      verify(new_lines, anchor, lcs_start, lcs_end)
    else
      {lcs_start, lcs_end, false}
    end
  end

  # The caller already chose the line. True when the anchor is not still
  # recognizable there. Does not search the rest of the file.
  def drifted_at?(_content, _start_line, _end_line, anchor) when anchor in [nil, ""], do: false

  def drifted_at?(_content, start_line, _end_line, _anchor) when not is_integer(start_line),
    do: false

  def drifted_at?(content, start_line, end_line, anchor) do
    not anchored_at?(LineDiff.split_lines(content || ""), start_line, end_line, anchor)
  end

  defp verify(new_lines, anchor, lcs_start, lcs_end) do
    anchor_len = length(String.split(anchor, "\n"))

    if anchored_at?(new_lines, lcs_start, lcs_start + anchor_len - 1, anchor) do
      {lcs_start, lcs_start + anchor_len - 1, false}
    else
      case find_anchor(new_lines, anchor, lcs_start) do
        found when is_integer(found) and found > 0 ->
          {found, found + anchor_len - 1, false}

        _ ->
          {lcs_start, lcs_end, true}
      end
    end
  end

  defp anchored_at?(lines, start_line, end_line, anchor) do
    anchor_len = length(String.split(anchor, "\n"))

    if start_line >= 1 and start_line + anchor_len - 1 <= length(lines) and
         end_line >= start_line do
      candidate = lines |> Enum.slice(start_line - 1, anchor_len) |> Enum.join("\n")
      candidate == anchor or anchor_similar?(candidate, anchor)
    else
      false
    end
  end

  defp find_anchor(lines, anchor, preferred_start) do
    anchor_lines = String.split(anchor, "\n")
    anchor_len = length(anchor_lines)

    if anchor_len == 0 or length(lines) < anchor_len do
      0
    else
      matches =
        0..(length(lines) - anchor_len)
        |> Enum.filter(fn i ->
          Enum.slice(lines, i, anchor_len) |> Enum.join("\n") == anchor
        end)
        |> Enum.map(&(&1 + 1))

      case matches do
        [] ->
          0

        [only] ->
          only

        _ ->
          Enum.min_by(matches, fn match -> abs(match - preferred_start) end)
      end
    end
  end

  defp remap_lines(line_map, old_start, old_end, max_line) do
    start_line = mapped_line(line_map, old_start)
    end_line = mapped_line(line_map, old_end)
    start_line = start_line |> min(max_line) |> max(1)
    end_line = end_line |> min(max_line) |> max(start_line)
    {start_line, end_line}
  end

  defp mapped_line(line_map, old_line) do
    case Map.get(line_map, old_line) do
      nil -> old_line
      0 -> old_line
      line -> line
    end
  end

  defp anchor_similar?(candidate, anchor) do
    a = String.trim(candidate)
    b = String.trim(anchor)

    cond do
      a == b ->
        true

      a == "" or b == "" ->
        false

      true ->
        {shorter, longer} =
          if byte_size(a) <= byte_size(b), do: {a, b}, else: {b, a}

        (byte_size(shorter) >= 8 and
           (String.contains?(longer, shorter) or one_middle_cut?(shorter, longer))) or
          levenshtein_ratio(a, b) >= 0.7
    end
  end

  defp one_middle_cut?(short, long) do
    if byte_size(short) >= byte_size(long) do
      false
    else
      cuts =
        String.codepoints(short)
        |> Enum.reduce([0], fn cp, [last | _] = acc ->
          [last + byte_size(cp) | acc]
        end)

      Enum.any?(cuts, fn k ->
        prefix = binary_part(short, 0, k)
        suffix = binary_part(short, k, byte_size(short) - k)
        String.starts_with?(long, prefix) and String.ends_with?(long, suffix)
      end) or String.starts_with?(long, short)
    end
  end

  defp levenshtein_ratio(a, b) do
    ar = String.codepoints(a)
    br = String.codepoints(b)

    if ar == [] and br == [] do
      1.0
    else
      1 - levenshtein(ar, br) / max(length(ar), length(br))
    end
  end

  defp levenshtein(a, b) do
    {a, b} = if length(a) < length(b), do: {b, a}, else: {a, b}
    if b == [], do: length(a), else: levenshtein_rows(a, b)
  end

  defp levenshtein_rows(a, b) do
    lb = length(b)
    a_t = List.to_tuple(a)
    b_t = List.to_tuple(b)

    Enum.reduce(1..length(a), Enum.to_list(0..lb), fn i, prev ->
      prev_t = List.to_tuple(prev)

      1..lb
      |> Enum.reduce([i], fn j, acc ->
        cost = if elem(a_t, i - 1) == elem(b_t, j - 1), do: 0, else: 1
        del = elem(prev_t, j) + 1
        ins = hd(acc) + 1
        sub = elem(prev_t, j - 1) + cost
        [Enum.min([del, ins, sub]) | acc]
      end)
      |> Enum.reverse()
    end)
    |> List.last()
  end
end
