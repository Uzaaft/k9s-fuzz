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

      apps = forAllSystems (
        { pkgs, bombadil }:
        let
          fuzz = pkgs.writeShellApplication {
            name = "fuzz";
            runtimeInputs = [
              bombadil.default
              pkgs.k9s
              pkgs.kind
              pkgs.git
            ];
            text = ''
              root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              state="$root/.state"

              # Keep k9s and kube state local to the repo so fuzzing can't
              # touch your real config or clusters.
              export KUBECONFIG="$state/kubeconfig"
              export K9S_CONFIG_DIR="$state/k9s"
              export XDG_STATE_HOME="$state/xdg"
              mkdir -p "$K9S_CONFIG_DIR" "$XDG_STATE_HOME"

              if ! kind get clusters 2>/dev/null | grep -qx fuzz; then
                kind create cluster --name fuzz
              fi

              run="$state/runs/$(date +%Y%m%d-%H%M%S)"
              mkdir -p "$run"
              echo "fuzz: writing trace and k9s.log to $run" >&2

              exec bombadil terminal fuzz \
                --specification "$root/spec.ts" \
                --output-path "$run" \
                "$@" \
                -- k9s --readonly --logFile "$run/k9s.log"
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${bombadil.default}/bin/bombadil";
          };
          fuzz = {
            type = "app";
            program = "${fuzz}/bin/fuzz";
          };
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
