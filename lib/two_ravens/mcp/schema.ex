defmodule TwoRavens.MCP.Schema do
  @moduledoc false

  @max_request_id 128
  @max_text 1_000_000
  @selector_limit 32

  @doc false
  def tools do
    selector = selector()

    [
      discover_tool(),
      context_tool(selector),
      create_bundle_tool(selector),
      change_tool(selector),
      retry_tool()
    ]
  end

  defp discover_tool do
    tool(
      "ravens_discover",
      "List or search canonical modules/functions with paths and docs. Example: " <>
        ~s({"query":"delivery promise","limit":10}),
      true,
      %{
        type: "object",
        additionalProperties: false,
        required: ["query"],
        properties: %{
          query: %{type: "string", minLength: 1, maxLength: 200},
          limit: %{type: "integer", minimum: 1, maximum: 20},
          kinds: %{
            type: "array",
            minItems: 1,
            maxItems: 2,
            uniqueItems: true,
            items: %{type: "string", enum: ~w(module function)}
          }
        }
      }
    )
  end

  defp context_tool(selector) do
    tool(
      "ravens_context",
      "Read exact source/relationships for canonical focuses at one revision. " <>
        "Invalid siblings are reported independently.",
      true,
      %{
        type: "object",
        additionalProperties: false,
        required: ["select"],
        properties: %{select: selectors(selector)}
      }
    )
  end

  defp create_bundle_tool(selector) do
    tool(
      "ravens_create_bundle",
      "Create new Elixir modules from one text string. Example operation body: " <>
        ~s({"mode":"apply_if_valid","text":"defmodule Shop.Pricing do\\nend"}),
      false,
      %{
        type: "object",
        additionalProperties: false,
        required: ~w(mode text),
        properties: %{
          base_revision: non_empty_string(),
          mode: mode(),
          request_id: request_id(),
          text: bounded_text(),
          return: selectors(selector)
        }
      }
    )
  end

  defp change_tool(selector) do
    tool(
      "ravens_change",
      "Apply ordered exact entity edits. Each operation uses op plus only its relevant fields; " <>
        "source_bundle uses {op:create, kind:source_bundle, text:...}.",
      false,
      %{
        type: "object",
        additionalProperties: false,
        required: ["mode"],
        properties: %{
          base_revision: non_empty_string(),
          draft: non_empty_string(),
          draft_version: positive_integer(),
          mode: mode(),
          operations: %{
            type: "array",
            minItems: 1,
            maxItems: 100,
            items: operation()
          },
          request_id: request_id(),
          return: selectors(selector)
        }
      }
    )
  end

  defp retry_tool do
    tool(
      "ravens_retry",
      "Repair one retained malformed request with a small RFC 6902 patch; retained source is reused.",
      false,
      %{
        type: "object",
        additionalProperties: false,
        required: ~w(attempt attempt_version patch),
        properties: %{
          attempt: non_empty_string(),
          attempt_version: positive_integer(),
          patch: %{
            type: "array",
            minItems: 1,
            maxItems: 32,
            items: json_patch_operation()
          }
        }
      }
    )
  end

  defp tool(name, description, read_only?, input_schema) do
    %{
      name: name,
      description: description,
      annotations: %{
        destructiveHint: not read_only?,
        idempotentHint: read_only?,
        openWorldHint: false,
        readOnlyHint: read_only?
      },
      inputSchema: input_schema
    }
  end

  defp operation do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        op: %{type: "string", enum: ~w(create replace patch set delete rename move)},
        kind: %{type: "string", enum: ~w(source_bundle function clause module_form)},
        parent: non_empty_string(),
        target: non_empty_string(),
        text: bounded_text(),
        diff: bounded_text(),
        hash: non_empty_string(),
        handle: non_empty_string(),
        field: non_empty_string(),
        value: %{},
        cascade: %{type: "boolean"},
        to: non_empty_string(),
        before: non_empty_string(),
        after: non_empty_string()
      }
    }
  end

  defp json_patch_operation do
    %{
      type: "object",
      additionalProperties: false,
      required: ~w(op path),
      properties: %{
        op: %{type: "string", enum: ~w(add remove replace move)},
        path: %{type: "string", minLength: 1, maxLength: 500},
        from: %{type: "string", minLength: 1, maxLength: 500},
        value: %{}
      }
    }
  end

  defp selector do
    %{
      type: "object",
      additionalProperties: false,
      required: ~w(focus include),
      properties: %{
        focus: %{type: "string", minLength: 1, maxLength: 500},
        include: %{
          type: "array",
          minItems: 1,
          maxItems: 12,
          uniqueItems: true,
          items: %{
            type: "string",
            enum:
              ~w(source path clauses callers callees tests targets editable docs evidence functions forms)
          }
        }
      }
    }
  end

  defp selectors(selector),
    do: %{type: "array", minItems: 1, maxItems: @selector_limit, items: selector}

  defp request_id do
    %{
      type: "string",
      minLength: 1,
      maxLength: @max_request_id,
      pattern: "^[A-Za-z0-9][A-Za-z0-9._:-]*$"
    }
  end

  defp bounded_text,
    do: %{type: "string", minLength: 1, maxLength: @max_text}

  defp mode, do: %{type: "string", enum: ~w(apply_if_valid draft_only)}
  defp positive_integer, do: %{type: "integer", minimum: 1}
  defp non_empty_string, do: %{type: "string", minLength: 1}
end
