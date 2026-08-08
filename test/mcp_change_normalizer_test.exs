defmodule TwoRavens.MCPChangeNormalizerTest do
  use ExUnit.Case, async: true

  alias TwoRavens.MCP.ChangeNormalizer

  test "normalizes common operation and source collection aliases without trusting paths" do
    first = "defmodule AliasShop.One do\n  def value, do: 1\nend"
    second = "defmodule AliasShop.Two do\n  def value, do: 2\nend"

    request = %{
      "mode" => "apply_if_valid",
      "operations" => [
        %{
          "operation" => "create",
          "files" => [
            %{"path" => "lib/alias_shop/one.ex", "source" => first},
            %{"path" => "lib/alias_shop/two.ex", "source" => second}
          ]
        }
      ]
    }

    assert %{
             "operations" => [
               %{
                 "op" => "create",
                 "kind" => "source_bundle",
                 "text" => source
               }
             ]
           } = ChangeNormalizer.normalize(request)

    assert source == first <> "\n\n" <> second
  end

  test "leaves a mismatched caller path invalid so normal validation can retain it" do
    source = "defmodule AliasShop.Actual do\n  def value, do: :ok\nend"

    request = %{
      "operations" => [
        %{
          "operation" => "create",
          "sources" => [%{"path" => "lib/alias_shop/wrong.ex", "source" => source}]
        }
      ]
    }

    assert %{"operations" => [%{"op" => "create", "sources" => [_]}]} =
             ChangeNormalizer.normalize(request)
  end
end
