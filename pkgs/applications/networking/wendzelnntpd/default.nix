{ lib, stdenv, fetchFromGitHub
, bison, flex, libmhash, mysql80, sqlite
}:

stdenv.mkDerivation rec {
  pname = "wendzelnntpd";
  version = "2.1.3";

  src = fetchFromGitHub {
    owner = "cdpxe";
    repo = "WendzelNNTPd";
    rev = "v${version}";
    hash = "sha256-xx3l6qJMeTQLhIxIWPKzRRfAVexN2etZpj4I1fvOEiw=";
  };

  buildInputs = [ bison flex libmhash mysql80 sqlite ];

  postPatch = ''
    # The install target does a lot of things we don't want. In particular, we
    # don't want it to:
    # - try changing ownership/permissions in the Nix store
    # - try installing configuration files in /etc
    # - try creating a database in /var/spool
    sed -i -E '/chown|chmod|wendzelnntpd\.conf|\/var\/spool/d' Makefile
  '';

  DESTDIR = placeholder "out";
  CONFDIR = "/etc";
  configurePhase = "./configure";

  meta = with lib; {
    description = "An easy to configure Usenet server (NNTP daemon).";
    homepage = "https://cdpxe.github.io/WendzelNNTPd/";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ malvo ];
  };
}
