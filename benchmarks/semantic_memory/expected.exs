%{
  schema_version: 1,
  oracle_location: :outside_analyzed_projects,
  tasks: %{
    explain_intent: %{
      required: ["intent:calculate_final_price_after_tier_discount"],
      forbidden: ["intent:inferred"]
    },
    identify_callers: %{
      required: ["caller:function:RavensShop.Checkout.checkout/2"],
      forbidden: []
    },
    separate_test_meaning: %{
      required: [
        "test:requested:RavensShop.PricingTest",
        "test:derived:RavensShop.PricingTest",
        "coverage:unknown"
      ],
      forbidden: ["coverage:observed"]
    },
    change_impact: %{
      required: [
        "caller:function:RavensShop.Checkout.checkout/2",
        "test:derived:RavensShop.PricingTest"
      ],
      forbidden: []
    },
    continue_after_rename: %{
      required: [
        "identity:preserved",
        "intent:calculate_final_price_after_tier_discount",
        "focus:function:RavensShop.Pricing.final_total/2"
      ],
      forbidden: ["focus:function:RavensShop.Pricing.total/2", "intent:inferred"]
    },
    review_behavior: %{
      required: [
        "intent:calculate_final_price_after_tier_discount",
        "caller:function:RavensShop.Checkout.checkout/2",
        "test:requested:RavensShop.PricingTest",
        "test:derived:RavensShop.PricingTest",
        "coverage:unknown",
        "focus:function:RavensShop.Pricing.final_total/2"
      ],
      forbidden: ["coverage:observed", "intent:inferred"]
    }
  }
}
