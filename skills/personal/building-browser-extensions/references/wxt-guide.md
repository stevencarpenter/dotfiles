# WXT reference

Use this reference when the project already uses WXT or the user has selected it. Preserve the installed version and package manager. A browser-extension fix does not imply a WXT migration or upgrade.

## Setup

For a new WXT project, use the [official installation instructions](https://wxt.dev/guide/installation.html). Choose only the UI framework the extension needs. Do not scaffold a new project over an existing extension.

Inspect the generated package scripts before running commands. WXT's core commands are:

| Command | Purpose |
|---|---|
| `wxt` | Start development mode |
| `wxt -b firefox` | Develop for Firefox |
| `wxt build` | Build the default target |
| `wxt build -b firefox` | Build Firefox |
| `wxt zip` | Build a distribution archive |
| `wxt prepare` | Generate project types |

Run these through the project's package manager or existing scripts. Build only required browser targets; inspect each generated manifest and packaged output.

## Entrypoints

WXT derives extension entrypoints from files under its configured entrypoint directory. Common defaults are `background.ts`, `content.ts`, `popup.html`, and `options.html`. A larger entrypoint can use a directory with an index file.

Follow the [entrypoint reference](https://wxt.dev/guide/essentials/entrypoints.html) for supported names, lifecycle callbacks, and browser targeting. Register service-worker event listeners synchronously and keep durable state outside worker globals.

Use the existing `wxt.config.ts` for manifest fields, UI modules, and build configuration. A permission or host match needs a concrete consumer in the requested feature.

## Imports and browser targeting

Follow the project's configured auto-imports and generated TypeScript declarations. Check the [auto-import reference](https://wxt.dev/guide/essentials/config/auto-imports.html) before changing import paths; do not apply an old migration checklist to an unknown version.

WXT can select code and entrypoints by build target. See [browser targeting](https://wxt.dev/guide/essentials/target-different-browsers.html). Keep runtime capability checks when supported versions of the same browser differ.

## Verification

Run the existing type, test, and build commands affected by the change. Load the built extension and exercise the requested behavior. Recheck worker restart behavior when state or background logic changes, and inspect content-script styling when UI isolation changes.
