# Shared modules select behavior from lib/machines.nix.
# Keep only declarations unique to this host here.
{ ... }:
{
  imports = [ ../modules/darwin ];

}
