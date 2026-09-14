---
name: ubiquitous-language
description: Extract or refine a project glossary from the conversation and existing domain documentation, identify ambiguous terms, and propose canonical definitions.
disable-model-invocation: true
---

# Ubiquitous Language

Read the conversation and the existing project glossary. Prefer its current location and format, including a `CONTEXT.md` language section. If no glossary exists and a saved glossary is requested, use `UBIQUITOUS_LANGUAGE.md`.

Identify terms with multiple meanings, synonyms for the same concept, and distinctions that affect domain behavior. Propose a canonical term with a concise definition. Preserve established terms unless the evidence supports changing them.

Include only concepts meaningful to domain experts. A module or API name belongs only when it also names a domain concept.

A compact glossary can use:

| Term | Definition | Ambiguous aliases |
|---|---|---|
| Order | A customer's request to purchase items. | Purchase, transaction |
| Invoice | A request for payment for delivered items. | Bill |

Add relationships and cardinality when established. Use a short scenario only when it clarifies a distinction the definitions cannot express. Do not invent domain rules to fill an example dialogue.

Mark unresolved ambiguities separately from agreed definitions. Ask for judgment only where the conversation, code, and existing documentation do not resolve the distinction.

On subsequent runs, merge new terms and revised definitions into the same glossary. Do not create a second glossary or rename code as a side effect of documenting terminology.
