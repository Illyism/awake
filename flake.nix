{
  description = "Awake — keep your MacBook awake with the lid closed, with battery and thermal safety guards";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forSystems (
        pkgs:
        let
          awake = pkgs.stdenvNoCC.mkDerivation {
            pname = "awake";
            version = "1.0.2";
            src = ./.;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin $out/share/awake/sudoers.d
              install -m 0755 awake $out/bin/awake
              ln -s awake $out/bin/asleep
              install -m 0440 sudoers.d/awake $out/share/awake/sudoers.d/awake
              runHook postInstall
            '';
            meta = with pkgs.lib; {
              description = "Keep your MacBook awake with the lid closed, with battery and thermal guards";
              homepage = "https://il.ly/awake";
              license = licenses.mit;
              platforms = platforms.darwin;
              mainProgram = "awake";
            };
          };
        in
        {
          inherit awake;
          default = awake;
        }
      );

      darwinModules.awake = import ./nix/darwin-module.nix self;
      darwinModules.default = self.darwinModules.awake;
    };
}
