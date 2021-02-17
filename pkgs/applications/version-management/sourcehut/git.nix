{ lib
, fetchgit
, buildPythonPackage
, buildGoModule
, python
, srht
, pygit2
, scmsrht
}:
let
  version = "0.72.8";
  src = fetchgit {
    url = "https://git.sr.ht/~sircmpwn/git.sr.ht";
    rev = version;
    sha256 = "1ms4l4adcj86vippyarr5gm4qcdqvzj3inwplifgpr6fm36sw780";
  };


  buildShell = src: buildGoModule {
    inherit src version;
    pname = "gitsrht-shell";
    vendorSha256 = "1abyv2s5l3bs0iylpgyj3jri2hh1iy8fiadxm7g6l2vl58h0b9ba";
  };

  buildDispatcher = src: buildGoModule {
    inherit src version;
    pname = "gitsrht-dispatcher";
    vendorSha256 = "1lzkf13m54pq0gnn3bcxc80nfg76hgck4l8q8jpaicrsiwgcyrd9";
  };

  buildKeys = src: buildGoModule {
    inherit src version;
    pname = "gitsrht-keys";
    vendorSha256 = "1d94cqy7x0q0agwg515xxsbl70b3qrzxbzsyjhn1pbyj532brn7f";
  };

  buildUpdateHook = src: buildGoModule {
    inherit src version;
    pname = "gitsrht-update-hook";
    vendorSha256 = "0fwzqpjv8x5y3w3bfjd0x0cvqjjak23m0zj88hf32jpw49xmjkih";
  };

  updateHook = buildUpdateHook "${src}/gitsrht-update-hook";

in
buildPythonPackage rec {
  inherit src version;
  pname = "gitsrht";

  nativeBuildInputs = srht.nativeBuildInputs;

  propagatedBuildInputs = [
    srht
    pygit2
    scmsrht
  ];

  preBuild = ''
    export PKGVER=${version}
    export SRHT_PATH=${srht}/${python.sitePackages}/srht
  '';

  postInstall = ''
    mkdir -p $out/bin
    cp ${buildShell "${src}/gitsrht-shell"}/bin/gitsrht-shell $out/bin/gitsrht-shell
    cp ${buildDispatcher "${src}/gitsrht-dispatch"}/bin/gitsrht-dispatch $out/bin/gitsrht-dispatch
    cp ${buildKeys "${src}/gitsrht-keys"}/bin/gitsrht-keys $out/bin/gitsrht-keys
    cp ${updateHook}/bin/gitsrht-update-hook $out/bin/gitsrht-update-hook
  '';
  passthru = {
    inherit updateHook;
  };

  meta = with lib; {
    homepage = "https://git.sr.ht/~sircmpwn/git.sr.ht";
    description = "Git repository hosting service for the sr.ht network";
    license = licenses.agpl3;
    maintainers = with maintainers; [ eadwu ];
  };
}
