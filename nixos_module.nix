# TODO  Validate this module
{ name, start_function, default_runtime_args, ... }:
{config, lib, pkgs, ...}: {
  options.services."${name}" = {
    enable = lib.mkEnable "${name} web service";
    runtimeConfiguration = lib.mkOption {
      type = lib.types.attrs;
      description = "Configuration to set for the web application";
      default = default_runtime_config;
    };
  };
  config.systemd.services."${name}" = lib.mkIf config.services."${name}".enable {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = "${startup config.services.${name}.runtimeConfiguration}";
    };
  };
}
