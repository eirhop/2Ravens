defmodule TwoRavens.SourceRange do
  @moduledoc "An exact, repository-relative source range."

  @enforce_keys [:path, :start_line, :start_column, :end_line, :end_column]
  defstruct [:path, :start_line, :start_column, :end_line, :end_column]

  @type t :: %__MODULE__{
          path: String.t(),
          start_line: pos_integer(),
          start_column: pos_integer(),
          end_line: pos_integer(),
          end_column: pos_integer()
        }
end
