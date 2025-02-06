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
  dbusLogging ? false,
  forceAppId ? null,
  renameDesktopFile ? true,
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
  skipExtraInstallCmds ? false,
  sensibleDefaults ? true,
}:
let
  standardDbusTalks = [
    "org.freedesktop.Notifications"
    "com.canonical.AppMenu.Registrar"
    "com.canonical.Unity.LauncherEntry"
    "org.freedesktop.ScreenSaver"
    "com.canonical.indicator.application"
    "org.kde.StatusNotifierWatcher"
    "org.freedesktop.portal.Documents"
    "org.freedesktop.portal.Flatpak"
    "org.freedesktop.portal.Desktop"
    "org.freedesktop.portal.Notifications"
    "org.freedesktop.portal.FileChooser"
  ];

  dbusCalls = [
    "org.freedesktop.portal.Desktop=org.freedesktop.portal.Settings.Read@/org/freedesktop/portal/desktop"
  ];

  dbusBroadcasts = [
    "org.freedesktop.portal.Desktop=org.freedesktop.portal.Settings.SettingChanged@/org/freedesktop/portal/desktop"
  ];

  standardSystemDbusTalks = [
    "com.canonical.AppMenu.Registrar"
    "com.canonical.Unity.LauncherEntry"
  ];

  buildFolderPath = path: "--ro-bind-try \"${path}\" \"${path}\"";

  buildFolderPathReadWrite = path: "--bind \"${path}\" \"${path}\"";

  folderPaths = paths: map (e: buildFolderPath e) paths;

  folderPathsReadWrite = paths: map (e: buildFolderPathReadWrite e) paths;

  dbusArgs =
    (lib.concatMapStrings (e: "    --talk=\"${e}\" \\\n") (
      lib.lists.unique (dbusTalks ++ (lib.optionals sensibleDefaults standardDbusTalks))
    ))
    + (lib.concatMapStrings (e: "    --own=\"${e}\" \\\n") dbusOwns)
    + (lib.optionalString sensibleDefaults (
      lib.concatMapStrings (e: "    --call=\"${e}\" \\\n") dbusCalls
    ))
    + (lib.optionalString sensibleDefaults (
      lib.concatMapStrings (e: "    --broadcast=\"${e}\" ") dbusBroadcasts
    ));

  systemDbusArgs = (
    lib.concatMapStrings (e: "--talk=${e} ") (
      lib.lists.unique (systemDbusTalks ++ (lib.optionals sensibleDefaults standardSystemDbusTalks))
    )
  );

  runtimeDirBinds = lib.optionals sensibleDefaults [
    "pulse"
  ];

  runtimeDirBindsArgs = map (
    e: "--ro-bind-try \"$XDG_RUNTIME_DIR/${e}\" \"$XDG_RUNTIME_DIR/${e}\""
  ) runtimeDirBinds;

  appId =
    if forceAppId != null then
      forceAppId
    else
      "nix.bwrapper.${builtins.replaceStrings [ "-" ] [ "_" ] pkg.pname}";

  mkSandboxPaths = builtins.concatStringsSep "\n" (
    map (
      e:
      let
        reservedMsg = "Sandbox path '${e.name}' is reserved. Please rename your sandbox path.";
      in
      assert lib.assertMsg (e.name != "config") reservedMsg;
      assert lib.assertMsg (e.name != "local") reservedMsg;
      assert lib.assertMsg (e.name != "cache") reservedMsg;
      assert lib.assertMsg (e.name != ".flatpak-info") reservedMsg;
      ''test -d "$HOME/.bwrapper/${pkg.pname}/${e.name}" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/${e.name}"''
    ) additionalSandboxPaths
  );

  mountSandboxPaths = map (
    e: ''--bind "$HOME/.bwrapper/${pkg.pname}/${e.name}" "${e.path}"''
  ) additionalSandboxPaths;

  buildFHSEnv = callPackage ./build-fhsenv-bubblewrap { inherit nixpkgs; };
in
assert lib.assertMsg (dieWithParent -> unsharePid) "dieWithParent requires unsharePid to be true.";
assert lib.assertMsg (
  (!renameDesktopFile) -> (forceAppId != null)
) "If you don't want to automatically rename the desktop file, you must specify an appId.";
{
  inherit buildFHSEnv;
  inherit
    runScript
    unshareIpc
    unshareUser
    unshareUts
    unshareCgroup
    unsharePid
    unshareNet
    privateTmp
    sensibleDefaults
    ;

  targetPkgs = pkgs: ((pkg.buildInputs or [ ]) ++ [ pkg ] ++ addPkgs);

  extraInstallCommands = lib.optionalString (!skipExtraInstallCmds) (
    ''
      # some fhsenv packages add these by default, but we want our own
      rm -rf $out/share/{applications,icons,pixmaps}

      mkdir -p $out/share/{applications,icons,pixmaps}

      test -d ${pkg}/share/icons && ln -s ${pkg}/share/icons/* $out/share/icons
      test -d ${pkg}/share/pixmaps && ln -s ${pkg}/share/pixmaps/* $out/share/pixmaps
    ''
    + (
      if renameDesktopFile then
        ''
          test $(ls ${pkg}/share/applications/*.desktop | wc -l) -eq 1 || (echo "You have chosen to automatically rename ${pkg.pname}'s desktop file, but there is more than 1. You will have to manually specify the appId using `forceAppId` instead." && exit 1)

          cp ${pkg}/share/applications/*.desktop $out/share/applications/${appId}.desktop
        ''
      else
        ''
          test -d ${pkg}/share/applications && cp ${pkg}/share/applications/* $out/share/applications
        ''
    )
    + (lib.optionalString overwriteExec ''
      sed -i "s|^Exec=.*|Exec=$out/bin/${runScript} ${execArgs}|" $out/share/applications/*.desktop
    '')
  );

  extraPreBwrapCmds =
    ''
      trap 'trap - SIGTERM && kill -- -$$' SIGINT SIGTERM EXIT

      test -d "$XDG_RUNTIME_DIR/app/${appId}" || mkdir -p "$XDG_RUNTIME_DIR/app/${appId}"
      test -d "$XDG_RUNTIME_DIR/doc/by-app/${appId}" || mkdir -p "$XDG_RUNTIME_DIR/doc/by-app/${appId}"
      test -d "$HOME/.bwrapper/${pkg.pname}/config" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/config"
      test -d "$HOME/.bwrapper/${pkg.pname}/local" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/local"
      test -d "$HOME/.bwrapper/${pkg.pname}/cache" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/cache"
      test -f "$HOME/.bwrapper/${pkg.pname}/.flatpak-info" && rm "$HOME/.bwrapper/${pkg.pname}/.flatpak-info"
      printf "[Application]\nname=${appId}\n" > "$HOME/.bwrapper/${pkg.pname}/.flatpak-info"
      ${mkSandboxPaths}

      ${lib.optionalString privateTmp ''test -d /tmp/app/${appId} || mkdir -p /tmp/app/${appId}''}

      set_up_dbus_proxy() {
        ${bubblewrap}/bin/bwrap \
          --new-session \
          --ro-bind /nix /nix \
          --bind "/run" "/run" \
          --ro-bind "$HOME/.bwrapper/${pkg.pname}/.flatpak-info" "/.flatpak-info" \
          --die-with-parent \
          --clearenv \
          -- \
          ${xdg-dbus-proxy}/bin/xdg-dbus-proxy "$DBUS_SESSION_BUS_ADDRESS" "$XDG_RUNTIME_DIR/app/${appId}/bus" --filter ${lib.optionalString dbusLogging "--log"} ${dbusArgs}
      }

      set_up_system_dbus_proxy() {
        ${bubblewrap}/bin/bwrap \
          --new-session \
          --ro-bind /nix /nix \
          --bind "/run" "/run" \
          --ro-bind "$HOME/.bwrapper/${pkg.pname}/.flatpak-info" "/.flatpak-info" \
          --die-with-parent \
          --clearenv \
          -- \
          ${xdg-dbus-proxy}/bin/xdg-dbus-proxy unix:path=/run/dbus/system_bus_socket "$XDG_RUNTIME_DIR/app/${appId}/bus_system" --filter ${lib.optionalString dbusLogging "--log"} ${systemDbusArgs}
      }

      set_up_dbus_proxy &
      set_up_system_dbus_proxy &
      ${coreutils}/bin/sleep 0.1

      ${lib.optionalString sensibleDefaults ''
        # there shouldn't be more than 1 xauth file, but best to be safe
        declare -a x11_auth_binds
        xauth_files=$(ls "$XDG_RUNTIME_DIR/xauth_"*)

        for file in $xauth_files; do
          x11_auth_binds+=(--ro-bind "$file" "$file")
        done

        # there also shouldn't be more than 1 of these sockets in theory, but best to be safe
        declare -a wayland_binds
        wayland_sockets=$(ls "$XDG_RUNTIME_DIR/wayland-"*)

        for file in $wayland_sockets; do
          wayland_binds+=(--ro-bind "$file" "$file")
        done

        declare -a pipewire_binds
        pipewire_sockets=$(ls "$XDG_RUNTIME_DIR/pipewire-"*)

        for file in $pipewire_sockets; do
          pipewire_binds+=(--ro-bind "$file" "$file")
        done
      ''}
    ''
    + (builtins.concatStringsSep "\n" (
      map (e: "test -d \"${e}\" || mkdir -p \"${e}\"") additionalFolderPathsReadWrite
    ));

  extraBwrapArgs =
    [
      "--new-session"
      "--tmpfs /home"
      "--tmpfs /mnt"
      "--tmpfs /run"
      "--ro-bind /run/current-system /run/current-system"
      "--ro-bind /run/booted-system /run/booted-system"
      "--ro-bind /run/opengl-driver /run/opengl-driver"
      "--ro-bind /run/opengl-driver-32 /run/opengl-driver-32"
      "--bind \"$XDG_RUNTIME_DIR/doc/by-app/${appId}\" \"$XDG_RUNTIME_DIR/doc\""
      "--bind \"$XDG_RUNTIME_DIR/app/${appId}/bus\" \"$XDG_RUNTIME_DIR/bus\""
      "--bind \"$XDG_RUNTIME_DIR/app/${appId}/bus_system\" /run/dbus/system_bus_socket"
      "--bind \"$HOME/.bwrapper/${pkg.pname}/config\" \"$HOME/.config\""
      "--bind \"$HOME/.bwrapper/${pkg.pname}/local\" \"$HOME/.local\""
      "--bind \"$HOME/.bwrapper/${pkg.pname}/cache\" \"$HOME/.cache\""
      "--setenv DBUS_SESSION_BUS_ADDRESS unix:path=\"$XDG_RUNTIME_DIR/bus\""
      "--setenv DISPLAY \"$DISPLAY\""
      "--setenv NOTIFY_IGNORE_PORTAL 1"
      "--setenv WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
    ]
    ++ (lib.optionals sensibleDefaults [
      "\"$\{x11_auth_binds[@]\}\""
      "\"$\{wayland_binds[@]\}\""
      "\"$\{pipewire_binds[@]\}\""
    ])
    ++ (lib.optional privateTmp ''--bind "/tmp/app/${appId}" "/tmp"'')
    ++ mountSandboxPaths
    ++ runtimeDirBindsArgs
    # common paths for cursor themes, fonts, etc.
    ++ (lib.optionals sensibleDefaults (folderPaths [
      "$HOME/.icons"
      "$HOME/.fonts"
      "$HOME/.themes"
      "$HOME/.config/gtk-3.0"
      "$HOME/.config/gtk-4.0"
      "$HOME/.config/gtk-2.0"
      "$HOME/.config/Kvantum"
      "$HOME/.config/gtkrc-2.0"
    ]))
    ++ (folderPaths additionalFolderPaths)
    ++ (folderPathsReadWrite additionalFolderPathsReadWrite)
    ++ appendBwrapArgs
    ++ [
      "--ro-bind \"$HOME/.bwrapper/${pkg.pname}/.flatpak-info\" \"/.flatpak-info\""
    ];
}
