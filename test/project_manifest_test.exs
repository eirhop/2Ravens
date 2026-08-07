defmodule TwoRavens.ProjectManifestTest do
  use ExUnit.Case, async: true

  alias TwoRavens.Authoring
  alias TwoRavens.Manifest
  alias TwoRavens.Project

  setup do
    root =
      Path.join(System.tmp_dir!(), "two-ravens-project-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "mix.exs"), "defmodule Temporary.MixProject do\nend\n")
    File.write!(Path.join(root, "lib/existing.ex"), "defmodule Existing do\nend\n")
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "initialization is deterministic and never changes existing source", %{root: root} do
    existing = File.read!(Path.join(root, "lib/existing.ex"))

    assert {:ok, %Manifest{managed_paths: []}} = Authoring.init(root)
    first_manifest = File.read!(Path.join(root, ".ravens/manifest"))
    assert {:ok, %Manifest{managed_paths: []}} = Authoring.init(root)

    assert File.read!(Path.join(root, ".ravens/manifest")) == first_manifest
    assert File.read!(Path.join(root, "lib/existing.ex")) == existing
    refute String.contains?(first_manifest, "defmodule")
  end

  test "managed paths cannot escape the project", %{root: root} do
    assert {:ok, project} = Project.open(root)
    assert {:error, %{code: :invalid_managed_path}} = Project.resolve(project, "../outside.ex")
    assert {:error, %{code: :invalid_managed_path}} = Project.resolve(project, "C:/outside.ex")
  end

  test "a corrupt or unsupported manifest fails explicitly", %{root: root} do
    File.mkdir_p!(Path.join(root, ".ravens"))
    File.write!(Path.join(root, ".ravens/manifest"), "schema_version=999\n")

    assert {:ok, project} = Project.open(root)
    assert {:error, %{code: :unsupported_manifest}} = Manifest.load(project)
  end
end
