{
  nixpkgs,
  runCommandLocal,
  callPackage,
  lib,
  xdg-dbus-proxy,
  bubblewrap,
  coreutils,
}:
{
  pkg,
  forceAppId ? null,
  renameDesktopFile ? true,
  dbusLogging ? false,
  runScript,
  appendBwrapArgs ? [ ],
  additionalFolderPaths ? [ ],
  additionalFolderPathsReadWrite ? [ ],
  additionalSandboxPaths ? [ ],
  dbusTalks ? [ ],
  dbusOwns ? [ ],
  systemDbusTalks ? [ ],
  addPkgs ? [ ],
  overwriteExec ? false,
  execArgs ? "",
  unshareIpc ? true,
  unshareUser ? false,
  unshareUts ? false,
  unshareCgroup ? false,
  unsharePid ? true,
  unshareNet ? false,
  dieWithParent ? true,
  privateTmp ? true,
  sensibleDefaults ? true,
}@args:
let
  mkFHSEnvArgs = callPackage ./mkFHSEnvArgs.nix { inherit nixpkgs; };

  fhsEnvArgs = mkFHSEnvArgs args;
in

fhsEnvArgs.buildFHSEnv (
  (builtins.removeAttrs fhsEnvArgs [ "buildFHSEnv" ])
  // {
    inherit (pkg) pname version meta;
  }
)
