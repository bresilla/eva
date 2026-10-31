# The test machine with eva taken as a bare store path, the way a binary
# cache hands it out: the module comes from the output itself, and the
# output carries no passthru or override.
{ eva, system ? builtins.currentSystem }:
let
  flake = builtins.getFlake (toString ../.);
  cached = path: {
    type = "derivation";
    name = builtins.substring 33 (-1) (baseNameOf path);
    outPath = builtins.appendContext path { ${path} = { path = true; }; };
    outputName = "out";
    outputs = [ "out" ];
  };
  machine = flake.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      (import "${cached eva}/nixos" {
        packages = _: {
          eva = cached eva;
          morf = flake.inputs.morf.packages.${system}.morf;
        };
      })
      ./machine.nix
    ];
  };
in
machine.config.system.build.toplevel.drvPath
