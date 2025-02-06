{
  nixpkgs,
  pkgs,
  runCommandLocal,
  callPackage,
  lib,
  xdg-dbus-proxy,
  bubblewrap,
  coreutils,
}:
{
  pkg-unwrapped ? null,
  dbusLogging ? false,
  forceAppId ? null,
  renameDesktopFile ? true,
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
  skipExtraInstallCmds ? true,
  sensibleDefaults ? true,
}@bwrapperArgs:
{
  name ? null,
  pname ? null,
  version ? null,
  runScript ? "bash",
  extraInstallCommands ? "",
  meta ? { },
  passthru ? { },
  extraPreBwrapCmds ? "",
  extraBwrapArgs ? [ ],
  unshareUser ? false,
  unshareIpc ? false,
  unsharePid ? false,
  unshareNet ? false,
  unshareUts ? false,
  unshareCgroup ? false,
  privateTmp ? false,
  dieWithParent ? true,
  ...
}@args:
let
  mkFHSEnvArgs = callPackage ./mkFHSEnvArgs.nix { inherit nixpkgs; };

  # TODO: is there a better way?
  pkg = bwrapperArgs.pkg-unwrapped or (builtins.elemAt (args.targetPkgs pkgs) 0);

  fhsEnvArgs = mkFHSEnvArgs (
    bwrapperArgs
    // {
      inherit
        runScript
        pkg

        # needed, because the default in this file differs from the default in mkFHSEnvArgs
        skipExtraInstallCmds
        ;
    }
  );

  pname = if args ? name && args.name != null then args.name else args.pname;
  versionStr = lib.optionalString (version != null) ("-" + version);
  name = pname + versionStr;

in
(fhsEnvArgs.buildFHSEnv (
  args
  // (builtins.removeAttrs fhsEnvArgs [ "buildFHSEnv" ])
  // {
    inherit name;

    targetPkgs = pkgs: ((fhsEnvArgs.targetPkgs pkgs) ++ (args.targetPkgs pkgs));

    extraInstallCommands = (args.extraInstallCommands or "") + fhsEnvArgs.extraInstallCommands;

    extraPreBwrapCmds = (args.extraPreBwrapCmds or "") + fhsEnvArgs.extraPreBwrapCmds;

    extraBwrapArgs = (args.extraBwrapArgs or [ ]) ++ fhsEnvArgs.extraBwrapArgs;
  }
))
