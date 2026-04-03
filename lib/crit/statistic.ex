defmodule Crit.Statistic do
  @moduledoc "Daily statistics row. One row per day, counters increment on create events."

  use Ecto.Schema

  @primary_key {:date, :date, autogenerate: false}

  schema "statistics" do
    field :reviews_created, :integer, default: 0
    field :comments_created, :integer, default: 0
    field :files_reviewed, :integer, default: 0
    field :lines_reviewed, :integer, default: 0
    field :bytes_stored, :integer, default: 0
    timestamps()
  end
end
