{
  lib,
  runCommandCC,
  pkg-config,
  gcr_4,
  glib,
  json-glib,
  roboto,
  material-symbols,
  ibm-plex,
  nerd-fonts,
  src,
  version,
  morf,
}:
let
  # Found by name: where a font package puts its files moves between
  # nixpkgs releases.
  fonts = [
    { package = roboto; name = "Roboto-Regular.ttf"; }
    { package = material-symbols; name = "MaterialSymbolsRounded*.ttf"; }
    { package = ibm-plex; name = "IBMPlexMono-Regular.otf"; }
    { package = nerd-fonts."m+"; name = "M+1NerdFont-Regular.ttf"; }
    { package = nerd-fonts.caskaydia-cove; name = "CaskaydiaCoveNerdFont-Regular.ttf"; }
  ];
in
# Everything eva installs, in one output:
#   share/eva     the shell, lock screen and greeter, with the Lua library of
#                 the morf it is built against and the faces it draws with
#   share/fonts   the whole families of those faces, for the system's fonts
#   bin           eva-keyring, the bridge for GNOME Keyring prompts
#   nixos         the NixOS module, importable without eva's flake
runCommandCC "eva-${version}"
  {
    inherit version;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ gcr_4 glib json-glib ];
    strictDeps = true;
    passthru.fontPackages = map (font: font.package) fonts;
    meta = {
      description = "A desktop shell, lock screen and greeter for morf";
      homepage = "https://github.com/bresilla/eva";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    tree="$out/share/eva"
    mkdir -p "$tree"
    for part in shell lock greet themes models lib; do
      cp -R ${src}/$part "$tree/"
    done
    cp ${src}/morf.lua "$tree/morf.lua"
    chmod -R u+w "$out"
    mkdir -p "$tree/library"
    cp -R ${morf}/share/morf/library/lib "$tree/library/"
    mkdir -p "$tree/fonts" "$out/share/fonts"
    for part in shell lock greet; do
      if [ -d "$tree/$part/fonts" ] && [ ! -L "$tree/$part/fonts" ]; then
        cp -R "$tree/$part/fonts/." "$tree/fonts/"
      fi
      rm -rf "$tree/$part/fonts"
      ln -s ../fonts "$tree/$part/fonts"
      cat > "$tree/$part/appearance-default.json" <<'JSON'
    { "theme": "tsugumori", "font": "" }
    JSON
    done
    ${lib.concatMapStringsSep "\n" (font: ''
      found=$(find ${font.package}/share/fonts -name ${lib.escapeShellArg font.name} | sort | head -n 1)
      if [ -z "$found" ]; then
        echo "no ${font.name} in ${font.package}" >&2
        exit 1
      fi
      ln -s "$found" "$tree/fonts/"
      mkdir -p "$out/share/fonts/${font.package.pname or font.package.name}"
      cp -rs ${font.package}/share/fonts/. "$out/share/fonts/${font.package.pname or font.package.name}/"
    '') fonts}
    mkdir -p "$out/bin"
    $CC -std=gnu11 -O2 -Wall -Wextra -Werror ${src}/helpers/keyring/eva-keyring.c \
      $(pkg-config --cflags --libs gcr-4 gio-unix-2.0 json-glib-1.0) \
      -o "$out/bin/eva-keyring"
    cp -RL ${src}/nix/nixos "$out/nixos"
  ''
