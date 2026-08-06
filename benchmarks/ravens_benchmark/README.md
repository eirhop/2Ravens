# Ravens benchmark contract

This directory holds the acceptance contract for the consumer fixture in
[`dev/benchmark_app`](../../dev/benchmark_app/README.md).

- [`expected.exs`](expected.exs) defines exact context queries and required
  semantic facts without prescribing JSON, Markdown, or another transport.
- [`tasks.exs`](tasks.exs) freezes the prompts used before and after Ravens.
- [`baseline.md`](baseline.md) defines isolation, measurement, and scoring.

The contract intentionally lives outside the analyzed fixture. Otherwise its
expected node names, outcomes, and keywords would contaminate graph discovery.

Source ranges are exact acceptance evidence and must be updated deliberately
when fixture formatting moves relevant code. The fixture revision is recorded
with every measured run.
