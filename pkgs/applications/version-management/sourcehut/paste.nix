{ lib
, fetchgit
, buildPythonPackage
, srht
, pyyaml
, python
}:

buildPythonPackage rec {
  pname = "pastesrht";
  version = "0.12.1";

  src = fetchgit {
    url = "https://git.sr.ht/~sircmpwn/paste.sr.ht";
    rev = version;
    sha256 = "0mq41kdxsh4i7akc8436yd27xxpmzv5qd9bqjkk15x47nzc5s221";
  };

  nativeBuildInputs = srht.nativeBuildInputs;

  propagatedBuildInputs = [
    srht
    pyyaml
  ];

  preBuild = ''
    export PKGVER=${version}
    export SRHT_PATH=${srht}/${python.sitePackages}/srht
  '';

  meta = with lib; {
    homepage = "https://git.sr.ht/~sircmpwn/paste.sr.ht";
    description = "Ad-hoc text file hosting service for the sr.ht network";
    license = licenses.agpl3;
    maintainers = with maintainers; [ eadwu ];
  };
}
