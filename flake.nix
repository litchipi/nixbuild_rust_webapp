{
  description = "Builds a Rust web application";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/22.05;
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cargo2nix = {
      url = github:cargo2nix/cargo2nix;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs; flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        cargo2nix.overlays.default
      ];
    };
  in {
    lib = rec {
      build_backend = backend: let
        backend_targets = pkgs.rustBuilder.makePackageSet {
          inherit (backend) rustChannel rustVersion;
          packageFun = import backend.cargo2nix_file;
          fetchCrateAlternativeRegistry = pkgs.rustBuilder.rustLib.fetchCrateAlternativeRegistryExpensive;
        };
      in (backend_targets.workspace.backend {}).bin;

      build_frontend = name: frontend: import ./build_yarn_app.nix {
        name = "${name}_frontend";
        src = frontend.src;
        inherit pkgs;
        type = frontend.type;
      };

      startRustyWebApp = {name, args, database, ...}@cfg: let
        argsstr = builtins.concatStringsSep " " args;
        start_database = let
          pgctl_args = builtins.concatStringsSep " " [
            "-D ${database.dir}"
            "-l ${database.logfile}"
            "-o \"-p ${builtins.toString database.port}\""
            "-o \"--unix_socket_directories='${database.dir}'\""
          ];
        in pkgs.writeShellScript "${name}_start_database" ''
          set -e
          export PATH="$PATH:${pkgs.postgresql}/bin"
          mkdir -p ${database.dir}
          if [ ! -f ${database.dir}/PG_VERSION ]; then
            initdb -D ${database.dir} --no-locale --encoding=UTF8
            pg_ctl ${pgctl_args} start
            createuser -p ${builtins.toString database.port} -h ${database.dir} -d ${database.user}
            createdb -h ${database.dir} -p ${builtins.toString database.port} -U ${database.user} ${database.dbname}
          else
            pg_ctl ${pgctl_args} start
          fi
        '';
  
      # TODO  check connection to remote database
      check_connection_db = pkgs.writeShellScript "check_connection_db" ''
        # TODO
      '';

      dbstart = if database.local
        then "${start_database}"
        else "${check_connection_db}";

      dbstop = if database.local
        then ''
          if [ -f ${database.dir}/postmaster.pid ]; then
            ${pkgs.postgresql}/bin/pg_ctl -D ${database.dir} stop
          fi
        ''
        else "";
      in pkgs.writeShellScript "${name}_start" ((if database.enable
        then ''
          function interrupt() {
            echo -e -n "\033[1K\r"
            ${dbstop}
          }
          trap interrupt SIGINT

          if ! ${dbstart}; then
            tail ${database.logfile}
            exit 1;
          fi
        '' else "") + ''

          ${build_backend cfg.backend}/bin/backend ${argsstr} ${build_frontend name cfg.frontend}

        '' + (if database.enable then ''
          ${dbstop}
        '' else ""
      ));

      buildCi = ""; # TODO  Build CI to test and validate
    };
  });
}
