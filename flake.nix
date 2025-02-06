{
  description = "A user-friendly method of sandboxing applications using bubblewrap with portals support.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
          ];
        };
      in
      {
        packages.brave-wrapped = pkgs.bwrapper {
          pkg = pkgs.brave;
          runScript = "brave";
        };

        packages.bottles-wrapped = pkgs.bottles.override {
          buildFHSEnv = pkgs.bwrapperFHSEnv {
            unshareIpc = false;
            systemDbusTalks = [
              "org.freedesktop.UDisks2"
            ];
            dbusOwns = [
              "com.usebottles.bottles"
            ];
          };
        };

        packages.lutris-wrapped = pkgs.lutris.override {
          buildFHSEnv = pkgs.bwrapperFHSEnv {
            unshareIpc = false;
            skipExtraInstallCmds = false;
            appendBwrapArgs = [
              "--setenv WEBKIT_DISABLE_DMABUF_RENDERER 1"
              "--setenv APPIMAGE_EXTRACT_AND_RUN 1"
            ];
            dbusTalks = [
              "org.freedesktop.Flatpak"
              "org.kde.StatusNotifierWatcher"
              "org.kde.KWin"
              "org.gnome.Mutter.DisplayConfig"
              "org.freedesktop.ScreenSaver"
            ];
            systemDbusTalks = [
              "org.freedesktop.UDisks2"
            ];
            dbusOwns = [
              "net.lutris.Lutris"
            ];
            additionalFolderPaths = [
              "$HOME/.config/kdedefaults"
              "$HOME/.local/share/color-schemes"
            ];
            additionalFolderPathsReadWrite = [
              "$HOME/.steam"
              "$HOME/.local/share/steam"
              "$HOME/.local/share/applications"
              "$HOME/.local/share/desktop-directories"
              "$HOME/Games"
              "$HOME/Documents/My Games"
              "/mnt/veracrypt1/Games/Lutris"
              "/mnt/veracrypt1/Games/Steam"
            ];
          };
        };

        packages.discord-wrapped = pkgs.bwrapper {
          pkg = pkgs.discord;
          runScript = "discord";
          overwriteExec = true;
          additionalFolderPathsReadWrite = [
            "$XDG_RUNTIME_DIR/app/com.discordapp.Discord"
          ];
          dbusOwns = [
            "com.discordapp.Discord"
          ];
        };
      }
    ))
    // {
      overlays.default = final: prev: {
        bwrapper = final.callPackage ./bwrapper.nix {
          inherit nixpkgs;
        };

        bwrapperFHSEnv = final.callPackage ./bwrapperFHSEnv.nix {
          inherit nixpkgs;
        };
      };
    };
}
