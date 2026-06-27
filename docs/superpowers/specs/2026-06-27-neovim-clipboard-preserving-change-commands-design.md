# Neovim Clipboard-Preserving Change Commands

## Problem

LazyVim sets `clipboard=unnamedplus` for local sessions, making Neovim's unnamed register the macOS
pasteboard. Change commands such as `ci"` write removed text to the unnamed register, replacing text
copied from another macOS application before it can be pasted.

The current config already sends `d` and `x` operations to the black-hole register, but change
commands remain unprotected.

## Design

Add normal- and visual-mode mappings for `c`, `C`, `s`, and `S` that prefix their existing commands
with the black-hole register (`"_`). This covers operator changes such as `ci"`, `ci{`, `cw`, and
`cc`, plus change-to-end-of-line and substitute commands.

Keep `clipboard=unnamedplus` unchanged. Normal `y`, `p`, and `P` behavior therefore remains integrated
with the macOS clipboard, while text discarded by change commands does not replace clipboard content.
Existing `d` and `x` mappings remain unchanged.

## Verification

Load the deployed configuration in headless Neovim and assert that each change mapping resolves to
its black-hole-register equivalent. Run formatting and repository hygiene checks relevant to the Lua
config, then apply the managed Neovim keymap file and confirm source/target parity.
