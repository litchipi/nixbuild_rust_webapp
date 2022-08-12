# Nix build Rust Web application

Builds a Web application using Rust as a backend.  

Can work with any frontend as long as this frontend uses `yarn` and uses one of these frameworks:
- React
- VueJS

The only condition is that the backend binary must accept the path of the frontend
assets to serve as the **last argument**.

Any other argument can be passed using the `args` attribute.

## Usage

Imagine you have a project like so:

```
+-backend/        # Rust backend
| | Cargo.nix
| | ...
|
+-frontend/       # React frontend
| | yarn.lock
| | ...
|
| flake.nix
```

Then you can do something like:
``` nix
inputs.build_rust_app.url = "github:litchipi/nixbuild_rust_webapp";
```

And in the outputs:
``` nix
defaultPackage = build_rust_app.lib.${system}.startRustyWebApp rec {
  name = "example";

  # Optionnal scripts you can set to be executed before / after
  scripts = {
    init = "# First thing";
    pre_exec = "# Prepare service execution";
    post_exec = "# Clean after service execution";
    exit = "# Last thing to do";
  };

  args = [
    "--port 8083"
  ];

  backend = {
    cargo2nix_file = ./backend/Cargo.nix;
    rustChannel = "stable";
    rustVersion = "1.61.0";
  };

  frontend = {
    src = ./frontend_react;
    type = "react";
  };
};
```

## Adding a database

The library can automate the creation of a `postgresql` database by doing:
``` nix
defaultPackage = build_rust_app.lib.${system}.startRustyWebApp rec {
  name = "example";

  # Optionnal scripts you can set to be executed before / after
  scripts = {
    init = "# First thing";
    pre_db = "# Prepare the creation of the database";
    pre_exec = "# Prepare service execution";
    post_exec = "# Clean after service execution";
    post_db = "# Clean after the database service is stopped";
    exit = "# Last thing to do";
  };

  args = [
    "--port 8083"
    "-h localhost"
    "-n ${database.dbname}"
    "-d ${builtins.toString database.port}"
    "-u ${database.user}"
  ];

  database = rec {
    enable = true;

    local = true;
    host = "localhost";
    port = 5435;

    dbname = "${name}db";
    user = "psql_${name}";
    dir = "/var/${name}/db";
    logfile = "${dir}/logs";
  };

  backend = {
    cargo2nix_file = ./backend/Cargo.nix;
    rustChannel = "stable";
    rustVersion = "1.61.0";
  };

  frontend = {
    src = ./frontend_react;
    type = "react";
  };
};
```
