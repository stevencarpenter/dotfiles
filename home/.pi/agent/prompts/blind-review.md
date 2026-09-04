Run the blind-review skill flow against {{target}} and present the merged report.

Load `/skill:blind-review` and follow it. The skill spawns a comment-blind
review pass and a full-context review pass, then merges them and surfaces
comment/code divergence. If a sub-agent extension is installed, run both
passes in parallel per the skill. Otherwise run them sequentially: blind
pass first (stripped tree only, no repo path in its brief), then the
context pass on the real tree.

Default target is the working diff against HEAD. Findings from this flow
are experimental: say so in the report.
