{ lib
, fetchgit
, buildPythonPackage
, srht
}:

buildPythonPackage rec {
  pname = "hubsrht";
  version = "0.12.1";

  src = fetchgit {
    url = "https://git.sr.ht/~sircmpwn/hub.sr.ht";
    rev = version;
    sha256 = "sha256-pqMp/+0D4hLwtX24oAzEDkHt55xHUTbUJHEsVUoavzA=";
  };

  nativeBuildInputs = srht.nativeBuildInputs;

  propagatedBuildInputs = [
    srht
  ];

  preBuild = ''
    export PKGVER=${version}
  '';

  dontUseSetuptoolsCheck = true;

  meta = with lib; {
    homepage = "https://git.sr.ht/~sircmpwn/hub.sr.ht";
    description = "Project hub service for the sr.ht network";
    license = licenses.agpl3;
    maintainers = with maintainers; [ eadwu ];
  };
}
