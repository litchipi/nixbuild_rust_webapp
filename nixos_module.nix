# TODO  Validate this module
{ name, ...}: startup: {config, lib, pkgs, ...}: {
  options.services."${name}".enable = lib.mkEnable "${name} web service";
  config.systemd.services."${name}" = lib.mkIf config.services."${name}".enable {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = "${startup}";
    };
  };
}
