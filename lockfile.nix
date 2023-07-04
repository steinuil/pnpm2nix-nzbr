{ lib
, runCommand
, remarshal
, fetchurl
, ...
}:

with lib;
let
  splitVersion = name: splitString "@" (head (splitString "(" name));
  getVersion = name: last (splitVersion name);
  withoutVersion = name: concatStringsSep "@" (init (splitVersion name));
in
rec {

  parseLockfile = lockfile: builtins.fromJSON (readFile (runCommand "toJSON" { } "${remarshal}/bin/yaml2json ${lockfile} $out"));

  dependencyTarballs = { registry, lockfile, packageOverrides }:
    unique (
      mapAttrsToList
        (n: v:
          if hasAttr n packageOverrides then packageOverrides.${n} else
          let
            name = withoutVersion n;
            baseName = last (splitString "/" (withoutVersion n));
            version = getVersion n;
          in
          fetchurl {
            url = "${registry}/${name}/-/${baseName}-${version}.tgz";
            sha512 = v.resolution.integrity;
          }
        )
        (parseLockfile lockfile).packages
    );

}
