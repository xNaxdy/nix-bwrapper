# Nix-Bwrapper

This is a very early attempt at creating a user-friendly method of sandboxing applications using bubblewrap with portals support. To do this, bwrapper leverages NixOS' built-in `buildFHSEnv` wrapper.

The `flake.nix` contains a minimal example using Brave browser.

## Usage

Import this flake like you would any other. It provides an overlay, which in turn provides the `bwrapper` "package" (it's a function, really).

Then, wrap any native package of your choosing using `bwrapper`.

Packages that are already using `buildFHSEnv` can be configured to use `bwrapperFHSEnv` instead, like so:

```nix
{
    bottles-wrapped = pkgs.bottles.override {
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
}
```

### `bwrapper`

The `bwrapper` function takes in a number of arguments and returns a package containing a shell script to run your sandboxed application, as well as any `.desktop` and icon files your application comes with. Below is an explanation of all arguments:

- `pkg` (package, required)

  The package providing the application you want to sandbox (e.g. `brave`).

- `runScript` (string, required)

  The name of the application (usually a file in the `bin` folder) to be run.

- `forceAppId` (string, optional)

  The app ID to use in the `/.flatpak-info` file. If left empty, this will be set to `nix.bwrapper.[package-name]`. Usually it is not necessary to override this, but some apps may force their own ID through other means (Lutris is one of those, for example).

  In this case, you will need to set this to the actual app ID, which can be retrieved using your window manager. For example, in KDE, you may use the KWin Debug Console in order to retrieve the app ID of any window (there it's called `resourceClass`).

- `dbusLogging` (boolean, optional)

  Whether to enable logging from `xdg-dbus-proxy`, useful for debugging purposes. (default false)

- `appendBwrapArgs` (array of string, optional)

  Arguments to be appended to the `bwrap` call to your sandboxed application. See `man bwrap` for help.

- `additionalFolderPaths` (array of path, optional)

  Additional folder paths to be made available read only within the sandbox. Supports environment variables. Example: `additionalFolderPaths: [ "$HOME/Documents" ]` to make your `Documents` folder available read only.

- `additionalFolderPathsReadWrite` (array of path, optional)

  Same as `additionalFolderPaths`, except the sandbox also gets write permissions.

- `additionalSandboxPaths` (array of object, optional)

  An array containing elements of type `{ name = "string"; path = "string"; }`. For each element, a sandboxed path will be created at `$HOME/.bwrapper/${name}` and mounted to `${path}` inside the sandbox. This is already done for `~/.config`, `~/.local` and `~/.cache` by default (unless `sensibleDefaults` is set to `false`). This is useful for ensuring data is kept persistently in the given paths.

  For example, for Firefox you'd want to add something like `additionalSandboxPaths: [ { name = "mozilla"; path = "$HOME/.mozilla"; }]` to ensure your browser settings are kept. Alternatively, you can also add `$HOME/.mozilla` to `additionalFolderPathsReadWrite`.

- `dbusTalks` (array of string, optional)

  A list of D-Bus services the sandboxed application is allowed to talk to. This is useful for applications that rely on D-Bus for things like notifications, or for applications that use D-Bus to communicate with other applications. For example, `org.freedesktop.secrets` is used by many applications to store passwords.

- `dbusOwns` (array of string, optional)

  A list of D-Bus services the sandboxed application is allowed to own. This is useful for applications that provide D-Bus services themselves.

- `systemDbusTalks` (array of string, optional)

  Same as `dbusTalks`, but for system D-Bus services.

- `addPkgs` (array of package, optional)

  A list of packages to be added to the sandbox, or more specifically, to be made available within the FHS environment. Although `/nix` is already mounted (which contains all applications as-is), some applications may not find them (especially if they've not been packaged for nix properly).

  By default, all libraries from the original package's `buildInputs` are already added, so normally you should be able to leave this field empty.

- `overwriteExec` (boolean, optional)
  If set to `true`, all `.desktop` files will be overwritten to point to the sandbox script. This is useful for applications that have absolute paths in the `Exec` field of their `.desktop` files.
- `execArgs` (string, optional)

  Arguments to be appended to the `Exec` field of the `.desktop` file. Useful mostly if you've set `overwriteExec` to `true`.

- `unshareIpc` (boolean, optional)

  If set to `true`, the sandbox will be created with `--unshare-ipc` set. (default true)

- `unshareUser` (boolean, optional)

  If set to `true`, the sandbox will be created with `--unshare-user` set. (default false)

- `unshareUts` (boolean, optional)

  If set to `true`, the sandbox will be created with `--unshare-uts` set. (default false)

- `unshareCgroup` (boolean, optional)

  If set to `true`, the sandbox will be created with `--unshare-cgroup` set. (default false)

- `unsharePid` (boolean, optional)

  If set to `true`, the sandbox will be created with `--unshare-pid` set. (default true)

- `unshareNet` (boolean, optional)

  If set to `true`, the sandbox will be created with `--unshare-net` set. (default false)

- `dieWithParent` (boolean, optional)

  If set to `true`, the sandbox will be created with `--die-with-parent` set. (default true)

- `privateTmp` (boolean, optional)

  If set to `true`, the sandbox will be created with a tmpfs mounted at `/tmp`. (default true)

- `sensibleDefaults` (boolean, optional)

  If set to `false`, will disable most of the preconfigured defaults. Note that this will most likely result in your application being unusable out of the box, so you will have to set up the required permissions yourself from scratch. (default true)

Examples:

```nix
{
    discord-wrapped = pkgs.bwrapper {
        pkg = pkgs.discord;
        runScript = "discord";
        overwriteExec = "discord";
        additionalFolderPathsReadWrite = [
            "$XDG_RUNTIME_DIR/app/com.discordapp.Discord" # for rich presence
        ];
    };

    slack-wrapped = pkgs.bwrapper {
        pkg = pkgs.slack;
        runScript = "slack";
        overwriteExec = true;
        execArgs = "-s %U";
        addPkgs = [
            pkgs.libdbusmenu # to make global menu work in KDE
        ];
        systemDbusTalks = [
            "org.freedesktop.UPower"
            "org.freedesktop.login1"
        ];
        dbusTalks = [
            "org.kde.kwalletd6"
            "org.freedesktop.secrets"
            "org.kde.kwalletd5"
        ];
    };
}

```

### Notes

`bwrapper` is preconfigured in such a way that it should integrate with your DE and your theming. By default, access to the following dbus services is granted:

```nix
{
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
}
```

Additionally, `bwrapper` will attempt to bind `pulse`, `pipewire` and `wayland` sockets from `$XDG_RUNTIME_DIR`, as well as any `X11` sockets it can find.

As for directories, it will attempt to mount (read only) the following:

```nix
"$HOME/.icons"
"$HOME/.fonts"
"$HOME/.themes"
"$HOME/.config/gtk-3.0"
"$HOME/.config/gtk-4.0"
"$HOME/.config/gtk-2.0"
"$HOME/.config/Kvantum"
"$HOME/.config/gtkrc-2.0"
```

Sandboxed files are stored in `$HOME/.bwrapper/[application-name]` on the host system.

Access is granted to all hardware devices by default.

### How to package a new application

#### Your application has a flatpak

First, obtain the info about the permissions the app needs:

1. Go to [flathub.org](https://flathub.org) and look for the application you want to wrap. We'll use [Slack](https://flathub.org/apps/com.slack.Slack) as an example here.

2. At the bottom, click on "Links", and then "Manifest". For Slack, it should lead you [here](https://github.com/flathub/com.slack.Slack).

3. Open the `.yaml` file, in this case `com.slack.Slack.yaml`

This file shows all the permissions that are being granted to the application. You can use this as a blueprint for which permissions to grant in your wrapper. We can see, that the file contains the following:

```yaml
finish-args:
  - --device=all
  - --env=XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons
  - --share=ipc
  - --share=network
  - --socket=pulseaudio
  - --socket=x11

  # Filesystems
  - --filesystem=xdg-download

  # D-Bus Access
  - --talk-name=com.canonical.AppMenu.Registrar
  - --talk-name=org.freedesktop.Notifications
  - --talk-name=org.freedesktop.ScreenSaver
  - --talk-name=org.freedesktop.secrets
  - --talk-name=org.kde.StatusNotifierWatcher
  - --talk-name=org.kde.kwalletd5
  - --talk-name=org.kde.kwalletd6

  # System D-Bus Access
  - --system-talk-name=org.freedesktop.UPower
  - --system-talk-name=org.freedesktop.login1
```

Now it's time to translate the above to nix. Let's first see what we can ignore:

- `--device=all` can be ignored, since `bwrapper` by default already grants access to all devices.

- `--env=XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons` can also be ignored, since the `$HOME/.icons` directory is mounted readonly as is, therefore this environment variable would only lead to confusion.

- `--socket=pulseaudio` and `--socket=x11` can be ignored, since pulseaudio and `X11` sockets are shared by default anyway.

That leaves the rest to be added. The final wrapper looks as follows:

```nix
{
    slack-wrapped = pkgs.bwrapper {
        # basic
        pkg = pkgs.slack;
        runScript = "slack";

        # needed, because in nix, the slack package
        # has the absolute path hardcoded to the Exec field
        overwriteExec = true;
        execArgs = "-s %U";

        # to make global menu work in KDE
        addPkgs = [
            pkgs.libdbusmenu
        ];

        # taken from the .yaml file above
        additionalFolderPathsReadWrite = [
            "$HOME/Downloads"
        ];
        dbusTalks = [
            "com.canonical.AppMenu.Registrar"
            "org.freedesktop.Notifications"
            "org.freedesktop.ScreenSaver"
            "org.freedesktop.secrets"
            "org.kde.StatusNotifierWatcher"
            "org.kde.kwalletd5"
            "org.kde.kwalletd6"
        ];
        systemDbusTalks = [
            "org.freedesktop.UPower"
            "org.freedesktop.login1"
        ];
    };
}
```

Note that even though e.g. `org.freedesktop.Notifications` is already granted by `bwrapper` by default, specifying it here again doesn't do any harm, since it filters for unique names anyway.

#### Your application does not have a flatpak

Begin with a minimal example (see the `flake.nix` for a minimal example using `brave`). Then, run your application from a terminal (to see the logs it outputs). Use it as you would normally, if you notice something doesn't work quite right (or at all), see if the terminal gives you a clue as to what's wrong. Amend your wrapper, and repeat.

As you might be able to tell, there's a lot of trial and error involved if you go down this route.

## Disclaimer

This project is still very much WIP, and as such things may not work as expected (or at all). Pull requests are welcome!
