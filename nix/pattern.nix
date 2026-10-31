{ stdenv, libxcrypt, python3, src }:
stdenv.mkDerivation {
  pname = "eva-pattern";
  version = "1";
  inherit src;
  buildInputs = [ libxcrypt ];
  buildPhase = ''
    $CC -std=c11 -O2 -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=2 \
      check.c -o eva-pattern-check -lcrypt
  '';
  installPhase = ''
    install -Dm755 eva-pattern-check "$out/libexec/eva-pattern-check"
    install -Dm755 eva-pattern "$out/bin/eva-pattern"
    substituteInPlace "$out/bin/eva-pattern" --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3 -I'
  '';
}
