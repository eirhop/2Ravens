defmodule TwoRavens.Repository do
  @moduledoc "Deterministic content hashes and repository revision identities."

  alias TwoRavens.Repository.Revision

  @doc "Returns the lowercase SHA-256 digest of a binary."
  @spec hash(binary()) :: String.t()
  def hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  @doc "Builds a revision from sorted managed-file hashes."
  @spec revision(String.t(), %{String.t() => String.t() | :missing}) :: Revision.t()
  def revision(root, file_hashes) do
    working_hash =
      file_hashes
      |> Enum.sort()
      |> :erlang.term_to_binary()
      |> hash()

    %Revision{
      git_revision: git_revision(root),
      working_hash: working_hash,
      file_hashes: file_hashes
    }
  end

  @doc "Returns the current commit only when the project root is itself a Git worktree."
  @spec git_revision(String.t()) :: String.t() | nil
  def git_revision(root) do
    with {top, 0} <-
           System.cmd("git", ["-C", root, "rev-parse", "--show-toplevel"], stderr_to_stdout: true),
         true <- same_path?(String.trim(top), root),
         {revision, 0} <-
           System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      String.trim(revision)
    else
      _ -> nil
    end
  end

  defp same_path?(left, right) do
    String.downcase(Path.expand(left)) == String.downcase(Path.expand(right))
  end
end
