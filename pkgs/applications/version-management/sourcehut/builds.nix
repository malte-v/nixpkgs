{ lib
, fetchgit
, buildPythonPackage
, buildGoModule
, srht
, redis
, celery
, pyyaml
, markdown
, ansi2html
, python
}:
let
  version = "0.66.1";

  buildWorker = src: buildGoModule {
    inherit src version;
    pname = "builds-sr-ht-worker";

    vendorSha256 = "sha256-giOaldV46aBqXyFH/cQVsbUr6Rb4VMhbBO86o48tRZY=";
  };
in
buildPythonPackage rec {
  inherit version;
  pname = "buildsrht";

  src = fetchgit {
    url = "https://git.sr.ht/~sircmpwn/builds.sr.ht";
    rev = version;
    sha256 = "sha256-g8YULtfnqYEHOOIcMWcwU/m36mqTJJOucoZ7azx7CBs=";
  };

  nativeBuildInputs = srht.nativeBuildInputs;

  propagatedBuildInputs = [
    srht
    redis
    celery
    pyyaml
    markdown
    ansi2html
  ];

  preBuild = ''
    export PKGVER=${version}
    export SRHT_PATH=${srht}/${python.sitePackages}/srht
  '';

  postInstall = ''
    mkdir -p $out/lib
    mkdir -p $out/bin/builds.sr.ht

    cp -r images $out/lib
    cp contrib/submit_image_build $out/bin/builds.sr.ht
    cp ${buildWorker "${src}/worker"}/bin/worker $out/bin/builds.sr.ht-worker
  '';

  meta = with lib; {
    homepage = "https://git.sr.ht/~sircmpwn/builds.sr.ht";
    description = "Continuous integration service for the sr.ht network";
    license = licenses.agpl3;
    maintainers = with maintainers; [ eadwu ];
  };
}
