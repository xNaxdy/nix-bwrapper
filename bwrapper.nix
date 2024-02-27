{ buildFHSEnv, lib, xdg-dbus-proxy, bubblewrap, coreutils }:
{ pkg
, runScript
, appendBwrapArgs ? [ ]
, additionalFolderPaths ? [ ]
, additionalFolderPathsReadWrite ? [ ]
, additionalSandboxPaths ? [ ]
, dbusTalks ? [ ]
, dbusOwns ? [ ]
, systemDbusTalks ? [ ]
, addPkgs ? [ ]
, overwriteExec ? false
, execArgs ? ""
, unshareIpc ? true
, unshareUser ? false
, unshareUts ? false
, unshareCgroup ? false
, unsharePid ? true
, unshareNet ? false
, dieWithParent ? true
, privateTmp ? true
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

  dbusArgs = (lib.concatMapStrings (e: "    --talk=\"${e}\" \\\n") (lib.lists.unique (dbusTalks ++ standardDbusTalks)))
    + (lib.concatMapStrings (e: "    --own=\"${e}\" \\\n") dbusOwns)
    + (lib.concatMapStrings (e: "    --call=\"${e}\" \\\n") dbusCalls)
    + (lib.concatMapStrings (e: "    --broadcast=\"${e}\" ") dbusBroadcasts);

  systemDbusArgs = (lib.concatMapStrings (e: "--talk=${e} ") (lib.lists.unique (systemDbusTalks ++ standardSystemDbusTalks)));

  runtimeDirBinds = [
    # we can't use $WAYLAND_DISPLAY here since if it's unset, it will just glob to /run/user/$uid/
    "wayland-0"
    "wayland-1"
    "pipewire-0"
    "pulse"
  ];

  runtimeDirBindsArgs = map (e: "--ro-bind-try \"$XDG_RUNTIME_DIR/${e}\" \"$XDG_RUNTIME_DIR/${e}\"") runtimeDirBinds;

  appId = "nix.bwrapper.${builtins.replaceStrings [ "-" ] [ "_" ] pkg.pname}";

  mkSandboxPaths = builtins.concatStringsSep "\n" (map
    (e:
      let
        reservedMsg = "Sandbox path '${e.name}' is reserved. Please rename your sandbox path.";
      in
      assert lib.assertMsg (e.name != "config") reservedMsg;
      assert lib.assertMsg (e.name != "local") reservedMsg;
      assert lib.assertMsg (e.name != "cache") reservedMsg;
      assert lib.assertMsg (e.name != ".flatpak-info") reservedMsg;
      ''test -d "$HOME/.bwrapper/${pkg.pname}/${e.name} || mkdir -p "$HOME/.bwrapper/${pkg.pname}/${e.name}"'')
    additionalSandboxPaths);

  mountSandboxPaths = map (e: ''--bind "$HOME/.bwrapper/${pkg.pname}/${e.name}" "${e.path}"'') additionalSandboxPaths;
in
assert lib.assertMsg (dieWithParent -> unsharePid) "dieWithParent requires unsharePid to be true.";

buildFHSEnv {
  inherit (pkg) pname version meta;
  inherit runScript unshareIpc unshareUser unshareUts unshareCgroup unsharePid unshareNet privateTmp;

  name = null;

  targetPkgs = pkgs: ((pkg.buildInputs or [ ]) ++ [ pkg ] ++ addPkgs);

  extraInstallCommands = ''
    mkdir -p $out/share/{applications,icons,pixmaps}

    test -d ${pkg}/share/applications && ln -s ${pkg}/share/applications/* $out/share/applications
    test -d ${pkg}/share/icons && ln -s ${pkg}/share/icons/* $out/share/icons
    test -d ${pkg}/share/pixmaps && ln -s ${pkg}/share/pixmaps/* $out/share/pixmaps

    # this is needed for exit code 0
    true
  '' + (lib.optionalString overwriteExec ''
    sed -i "s|^Exec=.*|Exec=$out/bin/${runScript} ${execArgs}|" $out/share/applications/*.desktop
  '');

  extraPreBwrapCmds = ''
    trap 'trap - SIGTERM && kill -- -$$' SIGINT SIGTERM EXIT

    test -d "$XDG_RUNTIME_DIR/app/${appId}" || mkdir "$XDG_RUNTIME_DIR/app/${appId}"
    test -d "$XDG_RUNTIME_DIR/doc/by-app/${appId}" || mkdir -p "$XDG_RUNTIME_DIR/doc/by-app/${appId}"
    test -d "$HOME/.bwrapper/${pkg.pname}/config" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/config"
    test -d "$HOME/.bwrapper/${pkg.pname}/local" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/local"
    test -d "$HOME/.bwrapper/${pkg.pname}/cache" || mkdir -p "$HOME/.bwrapper/${pkg.pname}/cache"
    test -f "$HOME/.bwrapper/${pkg.pname}/.flatpak-info" || printf "[Application]\nname=${appId}\n" > "$HOME/.bwrapper/${pkg.pname}/.flatpak-info"
    ${mkSandboxPaths}

    set_up_dbus_proxy() {
      ${bubblewrap}/bin/bwrap \
        --new-session \
        --ro-bind /nix /nix \
        --bind "/run" "/run" \
        --ro-bind "$HOME/.bwrapper/${pkg.pname}/.flatpak-info" "/.flatpak-info" \
        --die-with-parent \
        --clearenv \
        -- \
        ${xdg-dbus-proxy}/bin/xdg-dbus-proxy "$DBUS_SESSION_BUS_ADDRESS" "$XDG_RUNTIME_DIR/app/${appId}/bus" --filter ${dbusArgs}
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
        ${xdg-dbus-proxy}/bin/xdg-dbus-proxy unix:path=/run/dbus/system_bus_socket "$XDG_RUNTIME_DIR/app/${appId}/bus_system" --filter ${systemDbusArgs}
    }

    set_up_dbus_proxy &
    set_up_system_dbus_proxy &
    ${coreutils}/bin/sleep 0.1

    # TODO: idk if this is optimal...
    xauth_file=$(ls "$XDG_RUNTIME_DIR/xauth_"*)
  '' + (builtins.concatStringsSep "\n" (map (e: "test -d \"${e}\" || mkdir -p \"${e}\"") additionalFolderPathsReadWrite));

  extraBwrapArgs = [
    "--new-session"
    "--tmpfs /home"
    "--tmpfs /mnt"
    "--tmpfs \"$XDG_RUNTIME_DIR\""
    "--bind \"$XDG_RUNTIME_DIR/doc/by-app/${appId}\" \"$XDG_RUNTIME_DIR/doc\""
    "--bind \"$XDG_RUNTIME_DIR/app/${appId}/bus\" \"$XDG_RUNTIME_DIR/bus\""
    "--bind \"$XDG_RUNTIME_DIR/app/${appId}/bus_system\" /run/dbus/system_bus_socket"
    "--bind \"$HOME/.bwrapper/${pkg.pname}/config\" \"$HOME/.config\""
    "--bind \"$HOME/.bwrapper/${pkg.pname}/local\" \"$HOME/.local\""
    "--bind \"$HOME/.bwrapper/${pkg.pname}/cache\" \"$HOME/.cache\""
    "--setenv DBUS_SESSION_BUS_ADDRESS unix:path=\"$XDG_RUNTIME_DIR/bus\""
    "--setenv DISPLAY \"$DISPLAY\""
    "--setenv WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
    "--ro-bind \"$xauth_file\" \"$xauth_file\""
  ]
  ++ mountSandboxPaths
  ++ runtimeDirBindsArgs
  # common paths for cursor themes, fonts, etc.
  ++ (folderPaths [
    "$HOME/.icons"
    "$HOME/.fonts"
    "$HOME/.themes"
    "$HOME/.config/gtk-3.0"
    "$HOME/.config/gtk-4.0"
    "$HOME/.config/gtk-2.0"
    "$HOME/.config/Kvantum"
    "$HOME/.config/gtkrc-2.0"
  ])
  ++ (folderPaths additionalFolderPaths)
  ++ (folderPathsReadWrite additionalFolderPathsReadWrite)
  ++ appendBwrapArgs ++ [
    "--ro-bind \"$HOME/.bwrapper/${pkg.pname}/.flatpak-info\" \"/.flatpak-info\""
  ];
}
