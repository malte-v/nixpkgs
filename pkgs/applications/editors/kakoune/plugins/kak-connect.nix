{ stdenv, fetchFromGitHub }:
stdenv.mkDerivation {
  name = "kak-connect";
  version = "2020-11-01";
  src = fetchFromGitHub {
    owner = "alexherbo2";
    repo = "connect.kak";
    rev = "5ad59e5201d21ac1221be7c373bd25623efe8337";
    sha256 = "14vj55fgl7v3iyds1n0z2wsc9kh1cfnh1xl6k02wzbkdwiv7pyqw";
  };

  patchPhase = ''
    patchShebangs bin
  '';

  installPhase = ''
    cp -r bin $out/bin
    cp -r share $out/share
    mkdir -p $out/share/kak/autoload/plugins
    cp -r rc $out/share/kak/autoload/plugins/connect
  '';

  meta = with stdenv.lib;
  { description = "Kakoune extension to connect a program to Kakoune clients";
    homepage = "https://github.com/alexherbo2/connect.kak";
    license = licenses.unlicense;
    maintainers = with maintainers; [ malvo ];
    platform = platforms.all;
  };
}
