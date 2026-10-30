{
  lib,
  stdenv,
  pkg-config,
  gcr_4,
  glib,
  json-glib,
  src,
  version,
}:
stdenv.mkDerivation {
  pname = "morf-keyring";
  inherit version src;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ gcr_4 glib json-glib ];
  strictDeps = true;
  buildPhase = ''
    runHook preBuild
    $CC -std=gnu11 -O2 -Wall -Wextra -Werror morf-keyring.c \
      $(pkg-config --cflags --libs gcr-4 gio-unix-2.0 json-glib-1.0) \
      -o morf-keyring
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 morf-keyring "$out/bin/morf-keyring"
    runHook postInstall
  '';
  meta = {
    description = "eva's dialog bridge for GNOME Keyring";
    homepage = "https://github.com/bresilla/eva";
    license = lib.licenses.mit;
    mainProgram = "morf-keyring";
    platforms = lib.platforms.linux;
  };
}
