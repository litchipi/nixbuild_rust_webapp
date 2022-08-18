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
      db = {
        ensureUserExists = cfg: pkgs.writeShellScript "psql_ensure_${cfg.user}_user_exist" ''
          if ! ${pkgs.postgresql}/bin/psql -h ${cfg.dir} \
            -p ${builtins.toString cfg.port} -U ${cfg.user} \
            -n "${cfg.dbname}" \
            -c "SELECT * FROM pg_catalog.pg_user"|grep ${cfg.user} 1>/dev/null; then
            ${pkgs.postgresql}/bin/createuser -p ${builtins.toString cfg.port} -h ${cfg.dir} -d ${cfg.user}
          fi
        '';
        ensureDbExists = cfg: pkgs.writeShellScript "psql_ensure_${cfg.dbname}_db_exist" ''
          if ! ${pkgs.postgresql}/bin/psql -h ${cfg.dir} \
            -p ${builtins.toString cfg.port} -U ${cfg.user} -n "${cfg.dbname}" \
            -c "SELECT * FROM pg_catalog.pg_database" 1>/dev/null 2>/dev/null; then
            ${pkgs.postgresql}/bin/createdb -h ${cfg.dir} -p ${builtins.toString cfg.port} -U ${cfg.user} ${cfg.dbname}
          fi
        '';
      };

      build_backend = backend: let
        backend_targets = pkgs.rustBuilder.makePackageSet {
          inherit (backend) rustChannel rustVersion;
          packageFun = import backend.cargo2nix_file;
        };
      in (backend_targets.workspace.backend {}).bin;

      build_frontend = name: frontend: import ./build_yarn_app.nix {
        name = "${name}_frontend";
        src = frontend.src;
        inherit pkgs;
        type = frontend.type;
      };

      start_database = { name, database, ...}: let
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
          ${db.ensureUserExists database}
          ${db.ensureDbExists database}
        else
          pg_ctl ${pgctl_args} start
        fi
      '';

      startRustyWebApp =
      {
        name,
        database ? { required = false; spawn = false;},
        backend,
        frontend,
        args ? {},
        scripts ? {},
      ...}@buildconf:
      let
        argsstr = builtins.concatStringsSep " " (lib.attrsets.mapAttrsToList (arg: value: "${arg} ${value}") args);
        userscripts = {
          init=""; exit="";
          pre_db=""; post_db="";
          pre_exec=""; post_exec="";
        } // scripts;
  
        check_connection_db = ''
          ${pkgs.postgresql}/bin/pg_isready --quiet -h ${database.host} \
            -p ${builtins.toString database.port} \
            -U ${database.user} \
            -d ${database.dbname}
        '';

        dbstop = ''
          if [ -f ${database.dir}/postmaster.pid ]; then
            ${pkgs.postgresql}/bin/pg_ctl -D ${database.dir} stop
          fi
        '';
      in pkgs.writeShellScript "${name}_start" (''
          ${userscripts.init}

        '' + (if database.spawn
        then ''
          function interrupt() {
            echo -e -n "\033[1K\r"
            ${dbstop}
          }
          trap interrupt SIGINT

          ${userscripts.pre_db}
          if ! ${start_database buildconf}; then
            tail ${database.logfile}
            exit 1;
          fi
          ${userscripts.post_db}

        '' else "") + (if database.required then ''

          ${check_connection_db}

        '' else "") + ''

          ${userscripts.pre_exec}
          ${build_backend backend}/bin/backend ${argsstr} ${build_frontend name frontend}
          ${userscripts.post_exec}

        '' + (if database.spawn then ''
          ${dbstop}
        '' else "") + ''

          ${userscripts.exit}
        ''
      );

      # TODO  When start_database option, start database based on provided configs
      buildCi = config: let
        add_deps = builtins.concatStringsSep "\n" (builtins.map
          (dep:
            "export PATH=\"$PATH:${dep}/bin\""
          ) (config.ci.deps pkgs)
        );
        prepare_ci = ''
          set -e
          ${add_deps}
          export CI_DIR=/tmp/ci_${config.name}
          mkdir -p $CI_DIR
        '';
      in pkgs.writeShellScript "${config.name}_ci" (''
        ${prepare_ci}
        # Executing CI scripts on backend
        cd ${config.backend.src}
        '' + (builtins.concatStringsSep "\n" (config.ci.backend_scripts)) + "\n" + ''
        # Executing CI scripts on frontend
        cd ${config.frontend.src}
      '' + (builtins.concatStringsSep "\n" (config.ci.frontend_scripts))
      );

      # Usage:  buildFlake (runargs: { your config }) { default run args }
      buildFlake = buildcfg_fct: default_args: let
        getargs = run: buildcfg_fct (nixpkgs.lib.attrsets.recursiveUpdate default_args run);
      in {
        packages = {
          default = startRustyWebApp (buildcfg_fct default_args);
          prepare = run: startRustyWebApp (getargs run);

          dbstart = run: start_database (getargs run);

          backend = run: build_backend (getargs run).backend;
          frontend = run: let
            buildconf = getargs run;
          in build_frontend buildconf.name buildconf.frontend;

          ci = run: buildCi (getargs run);
          docker = run: import ./docker_image.nix pkgs (getargs run) (startRustyWebApp (getargs run));

          # Usage:  override (initbuildcfg: { your build config here }) (initruncfg: buildconfig: { your run config here })
          override = new_buildconf: new_runconf: let
            newbuildconf_val = nixpkgs.lib.attrsets.recursiveUpdate buildconf (new_buildconf buildconf);
            runconf_final = runconf newbuildconf_val;
            newrunconf_val = nixpkgs.lib.attrsets.recursiveUpdate runconf_final (new_runconf runconf_final newbuildconf_val);
          in startRustyWebApp newbuildconf_val newrunconf_val;
        };

        apps = {
          default = {
            type = "app";
            program = "${startRustyWebApp buildconf (runconf buildconf)}";
          };

          ci = {
            type = "app";
            program = "${buildCi buildconf}";
          };
        };

        nixosModules = import ./nixos_module.nix buildconfig (startRustyWebApp buildconfig (runconf buildconfig));
      };
    };
  });
}
