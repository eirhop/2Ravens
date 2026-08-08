defmodule TwoRavens.Source.ModuleForm do
  @moduledoc "One module-owned Elixir form whose deeper semantics may be unknown."

  @enforce_keys [:id, :module, :form, :fingerprint, :source, :evidence]
  defstruct [:id, :module, :form, :fingerprint, :source, :evidence, semantics: :unknown]

  @type t :: %__MODULE__{
          id: String.t(),
          module: String.t(),
          form: String.t(),
          fingerprint: String.t(),
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t(),
          semantics: :unknown
        }
end
