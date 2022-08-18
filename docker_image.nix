# TODO    Validate this derivation
pkgs: { name, ...}: startup: pkgs.dockerTools.buildImage {
  inherit name;
  tag = name;
  config = {
    Cmd = [ "${startup}" ];
  };
}
