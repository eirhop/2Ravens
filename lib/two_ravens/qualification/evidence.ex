defmodule TwoRavens.Qualification.Evidence do
  @moduledoc "Explicit evidence for checks run against one authoring candidate."

  @enforce_keys [
    :profile,
    :parse,
    :round_trip,
    :format,
    :compile,
    :tests,
    :isolated,
    :accepted_graph,
    :output_bytes,
    :commands
  ]
  defstruct [
    :profile,
    :parse,
    :round_trip,
    :format,
    :compile,
    :tests,
    :isolated,
    :accepted_graph,
    :output_bytes,
    :commands
  ]

  @type check :: :pass | :not_run
  @type profile :: :unqualified_dry_run | :qualified_dry_run | :apply
  @type t :: %__MODULE__{
          profile: profile(),
          parse: :pass,
          round_trip: :pass,
          format: :pass,
          compile: check(),
          tests: check(),
          isolated: boolean(),
          accepted_graph: :pass | :not_run,
          output_bytes: non_neg_integer(),
          commands: non_neg_integer()
        }

  @doc "Returns truthful evidence for an in-memory, unqualified dry-run candidate."
  @spec unqualified_dry_run() :: t()
  def unqualified_dry_run do
    %__MODULE__{
      profile: :unqualified_dry_run,
      parse: :pass,
      round_trip: :pass,
      format: :pass,
      compile: :not_run,
      tests: :not_run,
      isolated: false,
      accepted_graph: :not_run,
      output_bytes: 0,
      commands: 0
    }
  end

  @doc "Returns evidence for a candidate qualified in an isolated project."
  @spec qualified(:qualified_dry_run | :apply, non_neg_integer(), pos_integer()) :: t()
  def qualified(profile, output_bytes, commands)
      when profile in [:qualified_dry_run, :apply] and is_integer(output_bytes) and
             output_bytes >= 0 and
             is_integer(commands) and commands > 0 do
    %__MODULE__{
      profile: profile,
      parse: :pass,
      round_trip: :pass,
      format: :pass,
      compile: :pass,
      tests: :pass,
      isolated: true,
      accepted_graph: :not_run,
      output_bytes: output_bytes,
      commands: commands
    }
  end

  @doc false
  @spec applied(non_neg_integer(), pos_integer()) :: t()
  def applied(output_bytes, commands), do: qualified(:apply, output_bytes, commands)
end
