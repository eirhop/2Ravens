common_response = [
  :status,
  :resolved_focus,
  :nodes,
  :relationships,
  :important_paths,
  :shared_context,
  :focus_specific_context,
  :selected_source,
  :evidence,
  :unresolved,
  :frontier,
  :freshness,
  :output_cost
]

full_include = [
  :docs,
  :typespecs,
  :source,
  :clauses,
  :patterns,
  :guards,
  :argument_mappings,
  :result_mappings,
  :tests,
  :otp,
  :evidence,
  :uncertainty
]

bounded_limit = %{unit: :utf8_bytes, max: 24_000}

%{
  schema_version: 1,
  purpose: :semantic_acceptance_oracle,
  transport_format: :intentionally_unspecified,
  fixture: %{
    root: "dev/benchmark_app",
    application: :ravens_benchmark,
    source_roots: ["config", "lib", "test"],
    excluded_roots: ["_build", "deps"],
    revision: :working_tree
  },
  source_ranges: %{
    "RavensBenchmark.Checkout.place/1#1" => %{
      file: "lib/ravens_benchmark/checkout.ex",
      line_start: 19,
      line_end: 19
    },
    "RavensBenchmark.Checkout.place/1#2" => %{
      file: "lib/ravens_benchmark/checkout.ex",
      line_start: 21,
      line_end: 28
    },
    "RavensBenchmark.Checkout.preview/1" => %{
      file: "lib/ravens_benchmark/checkout.ex",
      line_start: 34,
      line_end: 36
    },
    "RavensBenchmark.Pricing.total/2#1" => %{
      file: "lib/ravens_benchmark/pricing.ex",
      line_start: 14,
      line_end: 14
    },
    "RavensBenchmark.Pricing.total/2#2" => %{
      file: "lib/ravens_benchmark/pricing.ex",
      line_start: 16,
      line_end: 21
    },
    "RavensBenchmark.Pricing.add_line_total/2" => %{
      file: "lib/ravens_benchmark/pricing.ex",
      line_start: 23,
      line_end: 26
    },
    "RavensBenchmark.Discount.amount/2#1" => %{
      file: "lib/ravens_benchmark/discount.ex",
      line_start: 12,
      line_end: 12
    },
    "RavensBenchmark.Discount.amount/2#2" => %{
      file: "lib/ravens_benchmark/discount.ex",
      line_start: 13,
      line_end: 13
    },
    "RavensBenchmark.Discount.amount/2#3" => %{
      file: "lib/ravens_benchmark/discount.ex",
      line_start: 14,
      line_end: 14
    },
    "RavensBenchmark.Inventory.start_link/1" => %{
      file: "lib/ravens_benchmark/inventory.ex",
      line_start: 17,
      line_end: 19
    },
    "RavensBenchmark.Inventory.reserve/2" => %{
      file: "lib/ravens_benchmark/inventory.ex",
      line_start: 26,
      line_end: 29
    },
    "RavensBenchmark.Inventory.init/1" => %{
      file: "lib/ravens_benchmark/inventory.ex",
      line_start: 32,
      line_end: 32
    },
    "RavensBenchmark.Inventory.handle_call/3#1" => %{
      file: "lib/ravens_benchmark/inventory.ex",
      line_start: 35,
      line_end: 44
    },
    "RavensBenchmark.Inventory.available?/2" => %{
      file: "lib/ravens_benchmark/inventory.ex",
      line_start: 46,
      line_end: 48
    },
    "RavensBenchmark.Inventory.decrement/2" => %{
      file: "lib/ravens_benchmark/inventory.ex",
      line_start: 50,
      line_end: 54
    },
    "RavensBenchmark.Payment.charge/2" => %{
      file: "lib/ravens_benchmark/payment.ex",
      line_start: 14,
      line_end: 16
    },
    "RavensBenchmark.PaymentGateway.charge/2" => %{
      file: "lib/ravens_benchmark/payment_gateway.ex",
      line_start: 9,
      line_end: 9
    },
    "RavensBenchmark.PaymentGateway.Local.charge/2#1" => %{
      file: "lib/ravens_benchmark/payment_gateway/local.ex",
      line_start: 14,
      line_end: 14
    },
    "RavensBenchmark.PaymentGateway.Local.charge/2#2" => %{
      file: "lib/ravens_benchmark/payment_gateway/local.ex",
      line_start: 15,
      line_end: 15
    },
    "RavensBenchmark.CheckoutTest:places a VIP order through pricing, inventory, and payment" =>
      %{file: "test/ravens_benchmark/checkout_test.exs", line_start: 13, line_end: 22},
    "RavensBenchmark.CheckoutTest:returns the inventory failure without charging" => %{
      file: "test/ravens_benchmark/checkout_test.exs",
      line_start: 24,
      line_end: 33
    },
    "RavensBenchmark.CheckoutTest:retains reserved inventory when payment declines" => %{
      file: "test/ravens_benchmark/checkout_test.exs",
      line_start: 35,
      line_end: 44
    },
    "RavensBenchmark.CheckoutTest:previews an order through the shared pricing path" => %{
      file: "test/ravens_benchmark/checkout_test.exs",
      line_start: 46,
      line_end: 55
    },
    "RavensBenchmark.CheckoutTest:rejects an empty order at the entry point" => %{
      file: "test/ravens_benchmark/checkout_test.exs",
      line_start: 57,
      line_end: 61
    },
    "RavensBenchmark.InventoryTest:maps a reserve call to the handler and updates process state" =>
      %{file: "test/ravens_benchmark/inventory_test.exs", line_start: 6, line_end: 14}
  },
  invariants: %{
    response_sections: common_response,
    freshness: %{repository: :current, index: :fresh},
    provenance: [:file, :source_range, :revision, :derivation],
    external_source_policy: :collapse_unless_requested,
    unknown_relationship_policy: :retain_as_candidate_or_unresolved,
    source_materialization: :once_per_range,
    truncation_policy: :whole_items_with_explicit_frontier,
    required_source_evidence: :exact_range_from_source_ranges,
    required_relationship_evidence: [:type, :origin, :confidence, :source_range]
  },
  scenarios: [
    %{
      id: :repository_orientation,
      purpose: "Orient in the unfamiliar fixture without dumping dependency internals.",
      query: %{
        focus: [%{type: :repository, path: "."}],
        traversal: %{
          direction: :downstream,
          max_depth: 2,
          max_nodes_per_hop: 30,
          max_total_nodes: 80,
          relations: [:defines, :uses, :implements, :supervises],
          stop_at: [:external_dependency]
        },
        include: [:docs, :typespecs, :evidence, :uncertainty],
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        status: :complete_within_limits,
        required_nodes: [
          %{type: :application, id: "application:ravens_benchmark"},
          %{type: :module, id: "module:RavensBenchmark.Checkout"},
          %{type: :module, id: "module:RavensBenchmark.Pricing"},
          %{type: :module, id: "module:RavensBenchmark.Discount"},
          %{type: :module, id: "module:RavensBenchmark.Inventory"},
          %{type: :module, id: "module:RavensBenchmark.Payment"},
          %{type: :behaviour, id: "module:RavensBenchmark.PaymentGateway"},
          %{type: :module, id: "module:RavensBenchmark.PaymentGateway.Local"},
          %{type: :struct, id: "struct:RavensBenchmark.Order"}
        ],
        required_roles: %{
          entrypoints: ["RavensBenchmark.Checkout.place/1", "RavensBenchmark.Checkout.preview/1"],
          process: "RavensBenchmark.Inventory",
          shared_calculation: "RavensBenchmark.Pricing.total/2",
          external_boundary: "RavensBenchmark.PaymentGateway.charge/2"
        },
        forbidden_source: ["deps/**", "_build/**"],
        frontier: %{external_dependencies: :collapsed}
      }
    },
    %{
      id: :checkout_module_one_hop,
      purpose: "Inspect a module and one behavioral hop in both directions.",
      query: %{
        focus: [%{type: :module, module: RavensBenchmark.Checkout}],
        traversal: %{
          direction: :both,
          max_depth: 2,
          max_nodes_per_hop: 20,
          max_total_nodes: 40,
          relations: [:defines, :calls, :uses, :tested_by],
          stop_at: [:external_dependency]
        },
        include: [:docs, :typespecs, :tests, :evidence],
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        required_downstream: [
          "RavensBenchmark.Checkout.place/1",
          "RavensBenchmark.Checkout.preview/1",
          "RavensBenchmark.Pricing.total/2",
          "RavensBenchmark.Inventory.reserve/2",
          "RavensBenchmark.Payment.charge/2",
          "RavensBenchmark.Order"
        ],
        required_upstream: ["RavensBenchmark.CheckoutTest"],
        required_tests: [
          "places a VIP order through pricing, inventory, and payment",
          "returns the inventory failure without charging",
          "retains reserved inventory when payment declines",
          "previews an order through the shared pricing path",
          "rejects an empty order at the entry point"
        ],
        forbidden_nodes: ["RavensBenchmark.InventoryTest"]
      }
    },
    %{
      id: :place_execution_envelope,
      purpose: "Explain every domain outcome and ordered effect from the primary entry point.",
      query: %{
        focus: [
          %{type: :function, module: RavensBenchmark.Checkout, name: :place, arity: 1}
        ],
        traversal: %{
          direction: :downstream,
          max_depth: 7,
          max_nodes_per_hop: 25,
          max_total_nodes: 100,
          relations: [
            :calls,
            :dataflows_to,
            :sends,
            :handles,
            :implements,
            :reads,
            :writes
          ],
          stop_at: [:side_effect, :process_boundary, :external_dependency]
        },
        include: full_include,
        constraints: [
          %{
            argument: 1,
            abstract_value: %{
              struct: RavensBenchmark.Order,
              known_keys: [:id, :items, :customer_tier],
              id: :binary,
              items: {:list, %{known_keys: [:sku, :quantity, :unit_price]}},
              customer_tier: {:atom_set, [:standard, :vip]}
            }
          }
        ],
        limit: bounded_limit
      },
      expect: %{
        resolved_focus: ["function:RavensBenchmark.Checkout.place/1"],
        clauses: [
          %{
            ordinal: 1,
            pattern: "%RavensBenchmark.Order{items: []}",
            guard: nil,
            source: %{file: "lib/ravens_benchmark/checkout.ex", line_start: 19, line_end: 19}
          },
          %{
            ordinal: 2,
            pattern: "%RavensBenchmark.Order{id: order_id, items: items} = order",
            guard: "is_binary(order_id) and is_list(items)",
            source: %{file: "lib/ravens_benchmark/checkout.ex", line_start: 21, line_end: 28}
          }
        ],
        required_relationships: [
          %{
            type: :calls,
            from: "RavensBenchmark.Checkout.place/1#2",
            to: "RavensBenchmark.Pricing.total/2",
            call_site: %{file: "lib/ravens_benchmark/checkout.ex", line: 23},
            arguments: %{1 => "items", 2 => "order.customer_tier"},
            result: "{:ok, total}",
            condition: :second_place_clause
          },
          %{
            type: :calls,
            from: "RavensBenchmark.Checkout.place/1#2",
            to: "RavensBenchmark.Inventory.reserve/2",
            call_site: %{file: "lib/ravens_benchmark/checkout.ex", line: 24},
            arguments: %{1 => "order_id", 2 => "items"},
            result: "{:ok, _reservation}",
            condition: "Pricing.total/2 returned {:ok, total}"
          },
          %{
            type: :calls,
            from: "RavensBenchmark.Checkout.place/1#2",
            to: "RavensBenchmark.Payment.charge/2",
            call_site: %{file: "lib/ravens_benchmark/checkout.ex", line: 25},
            arguments: %{1 => "order_id", 2 => "total"},
            result: ":ok",
            condition: "Inventory.reserve/2 returned {:ok, reservation}"
          },
          %{
            type: :dataflows_to,
            from: "RavensBenchmark.Pricing.total/2:result.total",
            to: "RavensBenchmark.Payment.charge/2:argument.2"
          }
        ],
        important_paths: [
          [
            "RavensBenchmark.Checkout.place/1",
            "RavensBenchmark.Pricing.total/2",
            "RavensBenchmark.Discount.amount/2"
          ],
          [
            "RavensBenchmark.Checkout.place/1",
            "RavensBenchmark.Inventory.reserve/2",
            "message:{:reserve, order_id, quantities}",
            "RavensBenchmark.Inventory.handle_call/3",
            "state:RavensBenchmark.Inventory.stock"
          ],
          [
            "RavensBenchmark.Checkout.place/1",
            "RavensBenchmark.Payment.charge/2",
            "RavensBenchmark.PaymentGateway.Local.charge/2",
            "boundary:RavensBenchmark.PaymentGateway.charge/2"
          ]
        ],
        outcomes: [
          %{
            result: "{:error, :empty_order}",
            condition: :first_place_clause,
            effects: []
          },
          %{
            result: "{:error, :out_of_stock}",
            condition: "Inventory.available?/2 returned false",
            effects: [:inventory_message, :inventory_read, :stock_unchanged]
          },
          %{
            result: "{:error, :declined}",
            condition: "discounted total > 20_000",
            effects_in_order: [:inventory_decremented, :payment_attempted]
          },
          %{
            result: "{:ok, %{order_id: order_id, total: total}}",
            condition: "inventory available and payment accepted",
            effects_in_order: [:inventory_decremented, :payment_attempted]
          }
        ],
        required_tests: [
          "places a VIP order through pricing, inventory, and payment",
          "returns the inventory failure without charging",
          "retains reserved inventory when payment declines",
          "rejects an empty order at the entry point"
        ],
        unresolved: [
          %{
            relationship: "RavensBenchmark.Payment.charge/2 -> configured gateway",
            source_only_status: :candidate,
            compiler_reconciled_status: :confirmed,
            candidate: "RavensBenchmark.PaymentGateway.Local.charge/2"
          }
        ],
        frontier: %{
          "GenServer.call/2" => :process_boundary,
          "RavensBenchmark.PaymentGateway.Local.charge/2" => :external_effect_boundary,
          "Enum.reduce/3" => :external_dependency
        },
        forbidden_source: ["deps/**", "_build/**"]
      }
    },
    %{
      id: :vip_discount_constraint,
      purpose: "Prove that abstract inputs prune incompatible clauses without executing code.",
      query: %{
        focus: [
          %{type: :function, module: RavensBenchmark.Discount, name: :amount, arity: 2}
        ],
        traversal: %{
          direction: :downstream,
          max_depth: 1,
          max_nodes_per_hop: 10,
          max_total_nodes: 15,
          relations: [:calls, :dataflows_to],
          stop_at: [:external_dependency]
        },
        include: [:source, :clauses, :patterns, :guards, :evidence, :uncertainty],
        constraints: [
          %{argument: 1, abstract_value: %{numeric_range: %{min: 6_000, max: 6_000}}},
          %{argument: 2, abstract_value: %{literal: :vip}}
        ],
        limit: bounded_limit
      },
      expect: %{
        selected_clause: %{
          ordinal: 1,
          pattern: "amount(subtotal, :vip)",
          guard: "subtotal >= 5_000",
          outcome: 600,
          source: %{file: "lib/ravens_benchmark/discount.ex", line_start: 12, line_end: 12}
        },
        pruned_clauses: [2, 3],
        unresolved: [],
        frontier: %{}
      }
    },
    %{
      id: :out_of_stock_keyword_discovery,
      purpose: "Resolve a vague issue deterministically, then continue from a returned node.",
      query: %{
        focus: [%{type: :keywords, terms: ["out_of_stock"]}],
        traversal: %{
          direction: :both,
          max_depth: 0,
          max_nodes_per_hop: 20,
          max_total_nodes: 20,
          relations: [],
          stop_at: []
        },
        include: [:docs, :typespecs, :source, :tests, :evidence],
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        status: :ambiguous_focus,
        required_candidates: [
          "function:RavensBenchmark.Checkout.place/1",
          "function:RavensBenchmark.Inventory.reserve/2",
          "clause:RavensBenchmark.Inventory.handle_call/3#1",
          "test:RavensBenchmark.CheckoutTest:returns the inventory failure without charging"
        ],
        selection_policy: :do_not_choose_silently,
        continuation: %{
          focus: "clause:RavensBenchmark.Inventory.handle_call/3#1",
          direction: :downstream,
          expected_branches: [:stock_decremented, :stock_unchanged]
        }
      }
    },
    %{
      id: :pricing_callers_and_tests,
      purpose: "Find callers and behavior-covering tests before a public refactor.",
      query: %{
        focus: [
          %{type: :function, module: RavensBenchmark.Pricing, name: :total, arity: 2}
        ],
        traversal: %{
          direction: :upstream,
          max_depth: 3,
          max_nodes_per_hop: 20,
          max_total_nodes: 50,
          relations: [:calls, :tested_by],
          stop_at: [:public_entrypoint]
        },
        include: [:docs, :typespecs, :source, :tests, :evidence],
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        direct_callers: [
          "RavensBenchmark.Checkout.place/1",
          "RavensBenchmark.Checkout.preview/1"
        ],
        important_paths: [
          [
            "RavensBenchmark.CheckoutTest:places a VIP order through pricing, inventory, and payment",
            "RavensBenchmark.Checkout.place/1",
            "RavensBenchmark.Pricing.total/2"
          ],
          [
            "RavensBenchmark.CheckoutTest:previews an order through the shared pricing path",
            "RavensBenchmark.Checkout.preview/1",
            "RavensBenchmark.Pricing.total/2"
          ]
        ],
        forbidden_tests: ["RavensBenchmark.InventoryTest"]
      }
    },
    %{
      id: :checkout_multi_focus,
      purpose: "Return shared pricing once while preserving entry-point-specific behavior.",
      query: %{
        focus: [
          %{type: :function, module: RavensBenchmark.Checkout, name: :place, arity: 1},
          %{type: :function, module: RavensBenchmark.Checkout, name: :preview, arity: 1}
        ],
        traversal: %{
          direction: :downstream,
          max_depth: 5,
          max_nodes_per_hop: 20,
          max_total_nodes: 70,
          relations: [:calls, :dataflows_to, :sends, :handles, :implements, :writes],
          stop_at: [:side_effect, :process_boundary, :external_dependency]
        },
        include: full_include,
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        components: 1,
        shared_nodes: [
          "RavensBenchmark.Pricing.total/2",
          "RavensBenchmark.Pricing.add_line_total/2",
          "RavensBenchmark.Discount.amount/2"
        ],
        place_only_downstream_nodes: [
          "RavensBenchmark.Inventory.reserve/2",
          "RavensBenchmark.Inventory.handle_call/3",
          "RavensBenchmark.Payment.charge/2",
          "RavensBenchmark.PaymentGateway.Local.charge/2"
        ],
        preview_only_downstream_nodes: [],
        materialization_counts: %{
          "RavensBenchmark.Pricing.total/2:source" => 1,
          "RavensBenchmark.Discount.amount/2:source" => 1
        },
        ordering: [:focus, :connecting_paths, :shared_context, :place_context]
      }
    },
    %{
      id: :inventory_otp_path,
      purpose: "Connect a public GenServer call to its message, handler, branches, and state.",
      query: %{
        focus: [
          %{type: :function, module: RavensBenchmark.Inventory, name: :reserve, arity: 2}
        ],
        traversal: %{
          direction: :downstream,
          max_depth: 5,
          max_nodes_per_hop: 20,
          max_total_nodes: 50,
          relations: [:calls, :dataflows_to, :sends, :handles, :reads, :writes],
          stop_at: [:process_boundary, :external_dependency]
        },
        include: full_include,
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        required_relationships: [
          %{
            type: :sends,
            from: "RavensBenchmark.Inventory.reserve/2",
            to: "message:{:reserve, order_id, quantities}",
            via: "GenServer.call/2",
            process: "RavensBenchmark.Inventory",
            call_site: %{file: "lib/ravens_benchmark/inventory.ex", line: 28}
          },
          %{
            type: :handles,
            from: "message:{:reserve, order_id, quantities}",
            to: "RavensBenchmark.Inventory.handle_call/3#1",
            source: %{file: "lib/ravens_benchmark/inventory.ex", line_start: 35, line_end: 44},
            mappings: %{
              "message.order_id" => "handler.order_id",
              "message.quantities" => "handler.quantities"
            }
          },
          %{
            type: :reads,
            from: "RavensBenchmark.Inventory.handle_call/3#1",
            to: "state:RavensBenchmark.Inventory.stock"
          },
          %{
            type: :writes,
            from: "RavensBenchmark.Inventory.handle_call/3#1:available",
            to: "state:RavensBenchmark.Inventory.stock",
            transition: "stock -> decrement(stock, quantities)"
          }
        ],
        branches: [
          %{
            condition: "available?(stock, quantities)",
            reply: "{:ok, reservation}",
            next_state: "updated_stock"
          },
          %{
            condition: "not available?(stock, quantities)",
            reply: "{:error, :out_of_stock}",
            next_state: "stock"
          }
        ],
        required_tests: [
          "RavensBenchmark.InventoryTest:maps a reserve call to the handler and updates process state"
        ],
        unresolved: []
      }
    },
    %{
      id: :payment_boundary,
      purpose: "Distinguish configuration, runtime calls, callback contracts, and effects.",
      query: %{
        focus: [
          %{type: :function, module: RavensBenchmark.Payment, name: :charge, arity: 2}
        ],
        traversal: %{
          direction: :downstream,
          max_depth: 3,
          max_nodes_per_hop: 15,
          max_total_nodes: 30,
          relations: [:calls, :implements, :dataflows_to],
          stop_at: [:external_dependency, :side_effect]
        },
        include: full_include,
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        required_relationships: [
          %{
            type: :dataflows_to,
            from: "config:ravens_benchmark.payment_gateway",
            to: "RavensBenchmark.Payment:@gateway",
            evidence: "config/config.exs",
            source_only_confidence: :candidate,
            compiler_confidence: :confirmed,
            value: "RavensBenchmark.PaymentGateway.Local"
          },
          %{
            type: :calls,
            from: "RavensBenchmark.Payment.charge/2",
            to: "RavensBenchmark.PaymentGateway.Local.charge/2",
            call_site: %{file: "lib/ravens_benchmark/payment.ex", line: 15}
          },
          %{
            type: :implements,
            from: "RavensBenchmark.PaymentGateway.Local.charge/2",
            to: "RavensBenchmark.PaymentGateway.charge/2"
          }
        ],
        required_boundary: %{
          kind: :external_effect_contract,
          node: "RavensBenchmark.PaymentGateway.charge/2",
          reached_from: "RavensBenchmark.PaymentGateway.Local.charge/2"
        },
        forbidden_runtime_path: [
          [
            "RavensBenchmark.Payment.charge/2",
            "RavensBenchmark.PaymentGateway.charge/2"
          ]
        ],
        explanation: "The callback is a contract and boundary, not an executed function."
      }
    },
    %{
      id: :genserver_macro_relationship,
      purpose: "Retain source macro evidence separately from compiler-generated relationships.",
      query: %{
        focus: [%{type: :module, module: RavensBenchmark.Inventory}],
        traversal: %{
          direction: :downstream,
          max_depth: 2,
          max_nodes_per_hop: 20,
          max_total_nodes: 40,
          relations: [:invokes_macro, :expands_to, :implements],
          stop_at: [:external_dependency]
        },
        include: [:source, :clauses, :evidence, :uncertainty],
        constraints: [],
        limit: bounded_limit
      },
      expect: %{
        required_relationships: [
          %{
            type: :invokes_macro,
            from: "RavensBenchmark.Inventory",
            to: "GenServer.__using__/1",
            call_site: %{file: "lib/ravens_benchmark/inventory.ex", line: 6},
            origin: :source
          },
          %{
            type: :implements,
            from: "RavensBenchmark.Inventory.init/1",
            to: "GenServer.init/1",
            origin: :compiler_confirmed
          },
          %{
            type: :implements,
            from: "RavensBenchmark.Inventory.handle_call/3",
            to: "GenServer.handle_call/3",
            origin: :compiler_confirmed
          },
          %{
            type: :expands_to,
            from: "GenServer.__using__/1@RavensBenchmark.Inventory",
            to: "RavensBenchmark.Inventory.child_spec/1",
            origin: :compiler_generated
          }
        ],
        evidence_states: %{
          source_without_compilation: :macro_invocation_known_expansion_candidate,
          reconciled_compiler_output: :generated_relationship_confirmed
        },
        frontier: %{GenServer => :external_dependency_source_collapsed}
      }
    }
  ]
}
