{
  description = "Markdown preview for Vim and Neovim on goda.vim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    goda-nix = {
      url = "github:airRnot1106/goda.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, goda-nix, ... }:
    let
      version = "0.1.0";

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [
          "aarch64-darwin"
          "x86_64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ] (system: f nixpkgs.legacyPackages.${system});

      build = pkgs: rec {
        client = pkgs.buildNpmPackage {
          pname = "goda-mp-client";
          inherit version;
          src = ./client;
          npmDeps = pkgs.importNpmLock { npmRoot = ./client; };
          npmConfigHook = pkgs.importNpmLock.npmConfigHook;
          installPhase = ''
            runHook preInstall
            cp -r dist $out
            runHook postInstall
          '';
        };

        plugin = goda-nix.lib.buildGodaPlugin pkgs {
          inherit version;
          src = ./.;
          vendorHash = "sha256-v1b+wpIvsBIoZhvrzFDAZHTkAxhpJT4RxeQPGBV8o9I=";
          preBuild = ''
            rm -rf client/dist
            cp -r ${client} client/dist
            chmod -R u+w client/dist
          '';
        };

        goTest =
          name: nativeBuildInputs: command:
          plugin.binary.overrideAttrs (prev: {
            name = "goda-mp-${name}";
            doCheck = true;
            nativeBuildInputs = prev.nativeBuildInputs ++ nativeBuildInputs;
            __darwinAllowLocalNetworking = true;
            checkPhase = ''
              runHook preCheck
              export HOME=$TMPDIR
              ${command}
              runHook postCheck
            '';
            installPhase = "touch $out";
          });

        demo =
          editor:
          let
            init = pkgs.writeText "goda-mp-demo.vim" ''
              set runtimepath^=${plugin.godaVim},${plugin}
              autocmd VimEnter * PreviewMarkdown
            '';
            script = pkgs.writeShellApplication {
              name = "goda-mp-demo";
              text = ''
                dir=$(mktemp -d)
                trap 'rm -rf "$dir"' EXIT
                cp ${./demo}/* "$dir"
                chmod -R u+w "$dir"
                for i in $(seq 1 50); do
                  printf '\n## Section %s\n\nScroll target %s.\n' "$i" "$i" >> "$dir/sample.md"
                done
                ${pkgs.lib.getExe editor} --clean --cmd 'source ${init}' "$@" "$dir/sample.md"
              '';
            };
          in
          {
            type = "app";
            program = pkgs.lib.getExe script;
            meta.description = "Open a sample Markdown file in ${editor.pname} with only goda-mp.vim and goda.vim";
          };
      };
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          inherit (build pkgs) client plugin;
        in
        {
          inherit client;
          default = plugin;
          vim-plugin = plugin;
          goda-mp = plugin.binary;
          goda-vim = plugin.godaVim;
        }
      );

      apps = forAllSystems (
        pkgs:
        let
          inherit (build pkgs) demo;
        in
        {
          default = demo pkgs.neovim;
          neovim = demo pkgs.neovim;
          vim = demo pkgs.vim;
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          inherit (build pkgs) goTest;
        in
        {
          unit = goTest "unit" [ ] "go test ./internal/...";
          e2e = goTest "e2e" [
            pkgs.vim
            pkgs.neovim
          ] "GODA_MP_E2E_STRICT=1 go test -v -count=1 ./e2e";
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (build pkgs).plugin.binary.go
            pkgs.nodejs
            pkgs.vim
            pkgs.neovim
          ];
        };
      });
    };
}
