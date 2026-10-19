{
  lib,
  runCommand,
  roboto,
  material-symbols,
  ibm-plex,
  nerd-fonts,
  src,
  version,
  library,
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
# The shell, lock screen and greeter as one tree, with the Lua library of the
# morf it is built against and the fonts it draws with.
runCommand "eva-${version}"
  {
    inherit version;
    passthru.fontPackages = map (font: font.package) fonts;
    meta = {
      description = "A desktop shell, lock screen and greeter for morf";
      homepage = "https://github.com/bresilla/eva";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p "$out"
    for part in shell lock greet themes models; do
      cp -R ${src}/$part "$out/"
    done
    cp ${src}/morf.lua "$out/morf.lua"
    chmod -R u+w "$out"
    mkdir -p "$out/library"
    cp -R ${library}/share/morf/library/lib "$out/library/"
    mkdir -p "$out/fonts"
    for part in shell lock greet; do
      if [ -d "$out/$part/fonts" ]; then
        cp -R "$out/$part/fonts/." "$out/fonts/"
        rm -rf "$out/$part/fonts"
      fi
      cat > "$out/$part/appearance-default.json" <<'EOF'
    { "theme": "tsugumori", "font": "" }
    EOF
      ln -s ../fonts "$out/$part/fonts"
    done
    ${lib.concatMapStringsSep "\n" (font: ''
      found=$(find ${font.package}/share/fonts -name ${lib.escapeShellArg font.name} | sort | head -n 1)
      if [ -z "$found" ]; then
        echo "no ${font.name} in ${font.package}" >&2
        exit 1
      fi
      ln -s "$found" "$out/fonts/"
    '') fonts}
  ''
