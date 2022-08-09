# TODO    Validate this derivation
pkgs: { name, version, ...}: startup: pkgs.dockerTools.buildImage {
  inherit name;
  tag = name;
  config = {
    Cmd = [ "${startup}" ];
  };
}
