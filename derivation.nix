{ lib
, stdenv
, nodejs
, pkg-config
, callPackage
, runCommand
, ...
}:

with builtins; with lib; with callPackage ./lockfile.nix { };
let
  nodePkg = nodejs;
  pkgConfigPkg = pkg-config;
in
{
  mkPnpmPackage =
    { src
    , packageJSON ? src + "/package.json"
    , pnpmLockYaml ? src + "/pnpm-lock.yaml"
    , pnpmWorkspaceYaml ? src + "/pnpm-workspace.yaml"
    , pname ? (fromJSON (readFile packageJSON)).name
    , version ? (fromJSON (readFile packageJSON)).version or null
    , name ? if version != null then "${pname}-${version}" else pname
    , registry ? "https://registry.npmjs.org"
    , script ? "build"
    , distDir ? "dist"
    , installInPlace ? false
    , copyPnpmStore ? true
    , copyNodeModules ? false
    , extraNodeModuleSources ? [ ]
    , extraBuildInputs ? [ ]
    , nodejs ? nodePkg
    , pnpm ? nodejs.pkgs.pnpm
    , pkg-config ? pkgConfigPkg
    , packageOverrides ? { }
    , ...
    }@attrs:
    stdenv.mkDerivation (
      recursiveUpdate
        (rec {
          inherit src name;

          nativeBuildInputs = [ nodejs pnpm pkg-config ] ++ extraBuildInputs;

          configurePhase = ''
            export HOME=$NIX_BUILD_TOP # Some packages need a writable HOME
            export npm_config_nodedir=${nodejs}

            runHook preConfigure

            ${if installInPlace
              then passthru.nodeModules.buildPhase
              else ''
                ${if !copyNodeModules
                  then "ln -s"
                  else "cp -r"
                } ${passthru.nodeModules}/. node_modules
              ''
            }

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            pnpm run ${script}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mv ${distDir} $out

            runHook postInstall
          '';

          passthru = {
            attrs = removeAttrs [ "packageOverrides" ] attrs;

            pnpmStore =
              let
                deps = dependencyTarballs {
                  inherit registry packageOverrides;
                  lockfile = pnpmLockYaml;
                };
              in
              runCommand "${name}-pnpm-store"
                {
                  nativeBuildInputs = [ nodejs pnpm ];
                } ''
                mkdir -p $out

                store=$(pnpm store path)
                mkdir -p $(dirname $store)
                ln -s $out $(pnpm store path)

                echo ${concatStringsSep " " deps}

                pnpm store add ${concatStringsSep " " (deps)}
              '';

            nodeModules = stdenv.mkDerivation {
              name = "${name}-node-modules";
              nativeBuildInputs = [ nodejs pnpm ];

              unpackPhase = concatStringsSep "\n"
                (
                  map
                    (v:
                      let
                        nv = if isAttrs v then v else { name = "."; value = v; };
                      in
                      "cp -vr ${nv.value} ${nv.name}"
                    )
                    ([
                      { name = "package.json"; value = packageJSON; }
                      { name = "pnpm-lock.yaml"; value = pnpmLockYaml; }
                      { name = "pnpm-workspace.yaml"; value = pnpmWorkspaceYaml; }
                    ] ++ extraNodeModuleSources)
                );

              buildPhase = ''
                export HOME=$NIX_BUILD_TOP # Some packages need a writable HOME

                store=$(pnpm store path)
                mkdir -vp $(dirname $store)

                # solve pnpm: EACCES: permission denied, copyfile '/build/.pnpm-store
                ${if !copyPnpmStore
                  then "ln -s"
                  else "cp -RL"
                } ${passthru.pnpmStore} $(pnpm store path)

                ${lib.optionalString copyPnpmStore "chmod -R +w $(pnpm store path)"}

                pnpm install --frozen-lockfile --offline
              '';

              installPhase = ''
                cp -r node_modules/. $out
              '';
            };
          };

        })
        (attrs // {
          extraNodeModuleSources = null;
          packageOverrides = null;
        })
    );
}
