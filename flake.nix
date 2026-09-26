{
  description = "Property-based testing of the k9s TUI with Bombadil";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Deliberately not following our nixpkgs, so builds hit bombadil.cachix.org.
    bombadil.url = "github:antithesishq/bombadil";
  };

  nixConfig = {
    extra-substituters = [ "https://bombadil.cachix.org" ];
    extra-trusted-public-keys = [
      "bombadil.cachix.org-1:6L4epM9zwhEcAwouNgBa8ENtsgLNfedtQgqtdnQhZiM="
    ];
  };

  outputs =
    { nixpkgs, bombadil, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            bombadil = bombadil.packages.${system};
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, bombadil }:
        {
          bombadil = bombadil.default;
          # Type definitions / runtime for `@antithesishq/bombadil/terminal` specs.
          bombadil-npm = bombadil.npm-package;
          k9s = pkgs.k9s;
          default = bombadil.default;
        }
      );

      devShells = forAllSystems (
        { pkgs, bombadil }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bombadil.default
              k9s

              # A throwaway cluster for k9s to talk to.
              kind
              kubectl

              # Writing specs.
              bun
              typescript
              typescript-language-server
              biome

              nil
              nixfmt
            ];

            BOMBADIL_NPM_PACKAGE = "${bombadil.npm-package}";

            shellHook = ''
              # Keep k9s and kube state local to the repo so fuzzing can't touch
              # your real config or clusters.
              export KUBECONFIG="$PWD/.state/kubeconfig"
              export K9S_CONFIG_DIR="$PWD/.state/k9s"
              export XDG_STATE_HOME="$PWD/.state/xdg"
              mkdir -p "$K9S_CONFIG_DIR" "$XDG_STATE_HOME"
            '';
          };
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt);
    };
}
