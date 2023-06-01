{
  description = "Lorenz Leutgeb's Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:msteen/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lorenz = {
      url = "github:lorenzleutgeb/nur";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, home-manager, vscode-server, sops, lorenz, ... }:
    with builtins;
    with nixpkgs;

    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      makeDiskImage = (import "${nixpkgs}/nixos/lib/make-disk-image.nix");

      kebabCaseToCamelCase =
        replaceStrings (map (s: "-${s}") lib.lowerChars) lib.upperChars;

      importDirToAttrs = dir:
        listToAttrs (map (name: {
          name = kebabCaseToCamelCase (lib.removeSuffix ".nix" name);
          value = import (dir + "/${name}");
        }) (attrNames (readDir dir)));

      nixosSystemFor = preconfig:
        lib.nixosSystem {
          inherit system;
          specialArgs.inputs = inputs;

          modules = [
            nixpkgs.nixosModules.notDetected
            home-manager.nixosModules.home-manager
            sops.nixosModules.sops
            ({ config, ... }: {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = false;
                backupFileExtension = "bak";
                extraSpecialArgs.inputs = inputs;
                users = { specialArgs.super = config; };
                modules = [ vscode-server.homeModules.default ];
              };
            })
            {
              system.stateVersion = "23.05";
              system.configurationRevision =
                pkgs.lib.mkIf (self ? rev) self.rev;
              nixpkgs = { inherit pkgs; };
              nix.registry.nixpkgs.flake = nixpkgs;
            }
            preconfig
          ];
        };

    in rec {
      packages.${system} = {
        nc = makeDiskImage {
          inherit pkgs;
          inherit (pkgs) lib;
          diskSize = "auto"; # 240 * 1000 * 1000 * 1000; # 240GB
          format = "qcow2";
          config = nixosConfigurations.nc.config;
        };
        live = nixosConfigurations.live.config.system.build.isoImage;
      };

      nixosConfigurations =
        ((mapAttrs (id: _: nixosSystemFor (import (./os/host + "/${id}")))
          (readDir ./os/host))) // {
            live = lib.nixosSystem {
              inherit system;
              modules = [
                "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
              ];
            };
          };
    };
}
