{ lib
, fetchgit
, buildPythonPackage
, srht
, redis
, pyyaml
, buildsrht
, writeText
}:

buildPythonPackage rec {
  pname = "scmsrht";
  version = "0.22.8";

  src = fetchgit {
    url = "https://git.sr.ht/~sircmpwn/scm.sr.ht";
    rev = version;
    sha256 = "08j6z5q7s54xwvv134q7jipj7dixrk3wn6wklc4aq5sq07yaxq5i";
  };

  nativeBuildInputs = srht.nativeBuildInputs;

  propagatedBuildInputs = [
    srht
    redis
    pyyaml
    buildsrht
  ];

  preBuild = ''
    export PKGVER=${version}
  '';

  dontUseSetuptoolsCheck = true;

  meta = with lib; {
    homepage = "https://git.sr.ht/~sircmpwn/git.sr.ht";
    description = "Shared support code for sr.ht source control services.";
    license = licenses.agpl3;
    maintainers = with maintainers; [ eadwu ];
  };
}
