# Personal dev secrets — rendered to ~/.config/zsh/.personal.env by op-render
# (home/.local/bin/op-render) via 1Password inject. This template is
# public-safe: it contains only 1Password references, never secret values. Do
# NOT put literal secrets here. Vault mapping is authoritative in Linear
# SNUG-386. (Never write a literal 1Password ref scheme in a comment — inject
# scans the whole file and would try to resolve it.)
#
# Refs live in the Private vault: 4 pre-existing canonical items + a
# consolidated `m5-dev-env` item holding the rest.
export OPENAI_API_KEY="{{ op://Private/OPENAI_API_KEY/credential }}"
export OPENROUTER_TOKEN="{{ op://Private/OPENROUTER_TOKEN/credential }}"
export NUGS_EMAIL="{{ op://Private/nugs.net/username }}"
export NUGS_PASSWORD="{{ op://Private/nugs.net/password }}"
export CONTEXT7_API_KEY="{{ op://Private/m5-dev-env/CONTEXT7_API_KEY }}"
export CLAUDE_CODE_OAUTH_TOKEN="{{ op://Private/m5-dev-env/CLAUDE_CODE_OAUTH_TOKEN }}"
export LLM_API_KEY="{{ op://Private/m5-dev-env/LLM_API_KEY }}"
export STRIX_LLM="{{ op://Private/m5-dev-env/STRIX_LLM }}"
export AUTH_JWKS_URL="{{ op://Private/m5-dev-env/AUTH_JWKS_URL }}"
export CLERK_FRONTEND_API="{{ op://Private/m5-dev-env/CLERK_FRONTEND_API }}"
export CLERK_PUBLISHABLE_KEY="{{ op://Private/m5-dev-env/CLERK_PUBLISHABLE_KEY }}"
export CLERK_SECRET_KEY="{{ op://Private/m5-dev-env/CLERK_SECRET_KEY }}"
export E2E_TEST_USER_EMAIL="{{ op://Private/m5-dev-env/E2E_TEST_USER_EMAIL }}"
export E2E_TEST_USER_PASSWORD="{{ op://Private/m5-dev-env/E2E_TEST_USER_PASSWORD }}"
