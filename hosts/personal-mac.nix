# personal-mac — thin host shim.
#
# All real config lives in the shared module set and self-gates on the caps /
# identity threaded in from lib/machines.nix via specialArgs. Keep this file
# thin: only genuinely host-scoped declarations belong here.
{ ... }:
{
  imports = [ ../modules/darwin ];

  # ── host-scoped config ─────────────────────────────────────────────────
  # Per-host agenix secret declarations are added by T6 (secrets). Anything
  # that is truly unique to this box (and cannot be derived from the caps
  # table) goes below this line.
}
