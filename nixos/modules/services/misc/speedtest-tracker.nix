{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.speedtest-tracker;
  speedtest-tracker = cfg.package.override {
    dataDir = cfg.dataDir;
  };
  # speedtest-tracker = cfg.package;
  db = cfg.database;
  mail = cfg.mail;

  user = cfg.user;
  group = cfg.group;

  # shell script for local administration
  artisan = pkgs.writeScriptBin "speedtest-tracker" ''
    #! ${pkgs.runtimeShell}
    cd ${speedtest-tracker}
    sudo=exec
    if [[ "$USER" != ${user} ]]; then
      sudo='exec /run/wrappers/bin/sudo -u ${user}'
    fi
    $sudo ${pkgs.php}/bin/php artisan $*
  '';

  tlsEnabled = cfg.nginx.addSSL || cfg.nginx.forceSSL || cfg.nginx.onlySSL || cfg.nginx.enableACME;

in {
  imports = [
    (mkRemovedOptionModule [ "services" "speedtest-tracker" "extraConfig" ] "Use services.speedtest-tracker.config instead.")
    (mkRemovedOptionModule [ "services" "speedtest-tracker" "cacheDir" ] "The cache directory is now handled automatically.")
  ];

  options.services.speedtest-tracker = {
    enable = mkEnableOption "Speedtest-tracker";

    # package = mkPackageOption pkgs "speedtest-tracker" { };
    package = lib.mkOption {
      default = pkgs."speedtest-tracker";
      defaultText = lib.literalExpression "pkgs.speedtest-tracker";
      example = "pkgs.speedtest-tracker";
      description = "Which speedtest-tracker derivation to use";
      type = lib.types.package;
    };

    user = mkOption {
      default = "speedtest-tracker";
      description = "User speedtest-tracker runs as.";
      type = types.str;
    };

    group = mkOption {
      default = "speedtest-tracker";
      description = "Group speedtest-tracker runs as.";
      type = types.str;
    };

    appKeyFile = mkOption {
      description = ''
        A file containing the Laravel APP_KEY - a 32 character long,
        base64 encoded key used for encryption where needed. Can be
        generated with `head -c 32 /dev/urandom | base64`.
      '';
      example = "/run/keys/speedtest-tracker-appkey";
      type = types.path;
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.fqdnOrHostName;
      defaultText = lib.literalExpression "config.networking.fqdnOrHostName";
      example = "speedtest-tracker.example.com";
      description = ''
        The hostname to serve Speedtest-tracker on.
      '';
    };

    appURL = mkOption {
      description = ''
        The root URL that you want to host Speedtest-tracker on. All URLs in Speedtest-tracker will be generated using this value.
        If you change this in the future you may need to run a command to update stored URLs in the database. Command example: `php artisan speedtest-tracker:update-url https://old.example.com https://new.example.com`
      '';
      default = "http${lib.optionalString tlsEnabled "s"}://${cfg.hostname}";
      defaultText = ''http''${lib.optionalString tlsEnabled "s"}://''${cfg.hostname}'';
      example = "https://example.com";
      type = types.str;
    };

    dataDir = mkOption {
      description = "Speedtest-tracker data directory";
      default = "/var/lib/speedtest-tracker";
      type = types.path;
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Database host address.";
      };
      port = mkOption {
        type = types.port;
        default = 3306;
        description = "Database host port.";
      };
      name = mkOption {
        type = types.str;
        default = "speedtest-tracker";
        description = "Database name.";
      };
      user = mkOption {
        type = types.str;
        default = user;
        defaultText = literalExpression "user";
        description = "Database username.";
      };
      passwordFile = mkOption {
        type = with types; nullOr path;
        default = null;
        example = "/run/keys/speedtest-tracker-dbpassword";
        description = ''
          A file containing the password corresponding to
          {option}`database.user`.
        '';
      };
      createLocally = mkOption {
        type = types.bool;
        default = false;
        description = "Create the database and database user locally.";
      };
    };

    mail = {
      driver = mkOption {
        type = types.enum [ "smtp" "sendmail" ];
        default = "smtp";
        description = "Mail driver to use.";
      };
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Mail host address.";
      };
      port = mkOption {
        type = types.port;
        default = 1025;
        description = "Mail host port.";
      };
      fromName = mkOption {
        type = types.str;
        default = "Speedtest-tracker";
        description = "Mail \"from\" name.";
      };
      from = mkOption {
        type = types.str;
        default = "mail@speedtest-trackerapp.com";
        description = "Mail \"from\" email.";
      };
      user = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "speedtest-tracker";
        description = "Mail username.";
      };
      passwordFile = mkOption {
        type = with types; nullOr path;
        default = null;
        example = "/run/keys/speedtest-tracker-mailpassword";
        description = ''
          A file containing the password corresponding to
          {option}`mail.user`.
        '';
      };
      encryption = mkOption {
        type = with types; nullOr (enum [ "tls" ]);
        default = null;
        description = "SMTP encryption mechanism to use.";
      };
    };

    maxUploadSize = mkOption {
      type = types.str;
      default = "18M";
      example = "1G";
      description = "The maximum size for uploads (e.g. images).";
    };

    poolConfig = mkOption {
      type = with types; attrsOf (oneOf [ str int bool ]);
      default = {
        "pm" = "dynamic";
        "pm.max_children" = 32;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 2;
        "pm.max_spare_servers" = 4;
        "pm.max_requests" = 500;
      };
      description = ''
        Options for the speedtest-tracker PHP pool. See the documentation on `php-fpm.conf`
        for details on configuration directives.
      '';
    };

    nginx = mkOption {
      type = types.submodule (
        recursiveUpdate
          (import ../web-servers/nginx/vhost-options.nix { inherit config lib; }) {}
      );
      default = {};
      example = literalExpression ''
        {
          serverAliases = [
            "speedtest-tracker.''${config.networking.domain}"
          ];
          # To enable encryption and let let's encrypt take care of certificate
          forceSSL = true;
          enableACME = true;
        }
      '';
      description = ''
        With this option, you can customize the nginx virtualHost settings.
      '';
    };

    config = mkOption {
      type = with types;
        attrsOf
          (nullOr
            (either
              (oneOf [
                bool
                int
                port
                path
                str
              ])
              (submodule {
                options = {
                  _secret = mkOption {
                    type = nullOr str;
                    description = ''
                      The path to a file containing the value the
                      option should be set to in the final
                      configuration file.
                    '';
                  };
                };
              })));
      default = {};
      example = literalExpression ''
        {
          ALLOWED_IFRAME_HOSTS = "https://example.com";
          WKHTMLTOPDF = "/home/user/bins/wkhtmltopdf";
          AUTH_METHOD = "oidc";
          OIDC_NAME = "MyLogin";
          OIDC_DISPLAY_NAME_CLAIMS = "name";
          OIDC_CLIENT_ID = "speedtest-tracker";
          OIDC_CLIENT_SECRET = {_secret = "/run/keys/oidc_secret"};
          OIDC_ISSUER = "https://keycloak.example.com/auth/realms/My%20Realm";
          OIDC_ISSUER_DISCOVER = true;
        }
      '';
      description = ''
        Speedtest-tracker configuration options to set in the
        {file}`.env` file.

        Refer to <https://www.speedtest-trackerapp.com/docs/>
        for details on supported values.

        Settings containing secret data should be set to an attribute
        set containing the attribute `_secret` - a
        string pointing to a file containing the value the option
        should be set to. See the example to get a better picture of
        this: in the resulting {file}`.env` file, the
        `OIDC_CLIENT_SECRET` key will be set to the
        contents of the {file}`/run/keys/oidc_secret`
        file.
      '';
    };

  };

  config = mkIf cfg.enable {

    assertions = [
      { assertion = db.createLocally -> db.user == user;
        message = "services.speedtest-tracker.database.user must be set to ${user} if services.speedtest-tracker.database.createLocally is set true.";
      }
      { assertion = db.createLocally -> db.passwordFile == null;
        message = "services.speedtest-tracker.database.passwordFile cannot be specified if services.speedtest-tracker.database.createLocally is set to true.";
      }
    ];

    services.speedtest-tracker.config = {
      APP_KEY._secret = cfg.appKeyFile;
      APP_URL = cfg.appURL;
      DB_HOST = db.host;
      DB_PORT = db.port;
      DB_DATABASE = db.name;
      DB_USERNAME = db.user;
      MAIL_DRIVER = mail.driver;
      MAIL_FROM_NAME = mail.fromName;
      MAIL_FROM = mail.from;
      MAIL_HOST = mail.host;
      MAIL_PORT = mail.port;
      MAIL_USERNAME = mail.user;
      MAIL_ENCRYPTION = mail.encryption;
      DB_PASSWORD._secret = db.passwordFile;
      MAIL_PASSWORD._secret = mail.passwordFile;
      APP_SERVICES_CACHE = "/run/speedtest-tracker/cache/services.php";
      APP_PACKAGES_CACHE = "/run/speedtest-tracker/cache/packages.php";
      APP_CONFIG_CACHE = "/run/speedtest-tracker/cache/config.php";
      APP_ROUTES_CACHE = "/run/speedtest-tracker/cache/routes-v7.php";
      APP_EVENTS_CACHE = "/run/speedtest-tracker/cache/events.php";
      SESSION_SECURE_COOKIE = tlsEnabled;
    };

    environment.systemPackages = [ artisan ];

    services.mysql = mkIf db.createLocally {
      enable = true;
      package = mkDefault pkgs.mariadb;
      ensureDatabases = [ db.name ];
      ensureUsers = [
        { name = db.user;
          ensurePermissions = { "${db.name}.*" = "ALL PRIVILEGES"; };
        }
      ];
    };

    services.phpfpm.pools.speedtest-tracker = {
      inherit user;
      inherit group;
      phpOptions = ''
        log_errors = on
        post_max_size = ${cfg.maxUploadSize}
        upload_max_filesize = ${cfg.maxUploadSize}
      '';
      settings = {
        "listen.mode" = "0660";
        "listen.owner" = user;
        "listen.group" = group;
      } // cfg.poolConfig;
    };

    services.nginx = {
      enable = mkDefault true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      virtualHosts.${cfg.hostname} = mkMerge [ cfg.nginx {
        root = mkForce "${speedtest-tracker}/share/php/speedtest-tracker/public";
        locations = {
          "/" = {
            index = "index.php";
            tryFiles = "$uri $uri/ /index.php?$query_string";
          };
          "~ \\.php$".extraConfig = ''
            fastcgi_pass unix:${config.services.phpfpm.pools."speedtest-tracker".socket};
          '';
          "~ \\.(js|css|gif|png|ico|jpg|jpeg)$" = {
            extraConfig = "expires 365d;";
          };
        };
      }];
    };

    systemd.services.speedtest-tracker-setup = {
      description = "Preparation tasks for Speedtest-tracker";
      before = [ "phpfpm-speedtest-tracker.service" ];
      after = optional db.createLocally "mysql.service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        WorkingDirectory = "${speedtest-tracker}";
        RuntimeDirectory = "speedtest-tracker/cache";
        RuntimeDirectoryMode = "0700";
      };
      path = [ pkgs.replace-secret ];
      script =
        let
          isSecret = v: isAttrs v && v ? _secret && isString v._secret;
          speedtest-trackerEnvVars = lib.generators.toKeyValue {
            mkKeyValue = lib.flip lib.generators.mkKeyValueDefault "=" {
              mkValueString = v: with builtins;
                if isInt         v then toString v
                else if isString v then v
                else if true  == v then "true"
                else if false == v then "false"
                else if isSecret v then hashString "sha256" v._secret
                else throw "unsupported type ${typeOf v}: ${(lib.generators.toPretty {}) v}";
            };
          };
          secretPaths = lib.mapAttrsToList (_: v: v._secret) (lib.filterAttrs (_: isSecret) cfg.config);
          mkSecretReplacement = file: ''
            replace-secret ${escapeShellArgs [ (builtins.hashString "sha256" file) file "${cfg.dataDir}/.env" ]}
          '';
          secretReplacements = lib.concatMapStrings mkSecretReplacement secretPaths;
          filteredConfig = lib.converge (lib.filterAttrsRecursive (_: v: ! elem v [ {} null ])) cfg.config;
          speedtest-trackerEnv = pkgs.writeText "speedtest-tracker.env" (speedtest-trackerEnvVars filteredConfig);
        in ''
        # error handling
        set -euo pipefail

        # set permissions
        umask 077

        # create .env file
        install -T -m 0600 -o ${user} ${speedtest-trackerEnv} "${cfg.dataDir}/.env"
        ${secretReplacements}
        if ! grep 'APP_KEY=base64:' "${cfg.dataDir}/.env" >/dev/null; then
            sed -i 's/APP_KEY=/APP_KEY=base64:/' "${cfg.dataDir}/.env"
        fi

        # migrate db
        ${pkgs.php}/bin/php ${artisan} migrate --force
      '';
    };

    systemd.tmpfiles.settings."10-speedtest-tracker" = let
      defaultConfig = {
        inherit user group;
        mode = "0700";
      };
    in {
      "${cfg.dataDir}".d = defaultConfig // { mode = "0710"; };
      "${cfg.dataDir}/public".d = defaultConfig // { mode = "0750"; };
      "${cfg.dataDir}/public/uploads".d = defaultConfig // { mode = "0750"; };
      "${cfg.dataDir}/storage".d = defaultConfig;
      "${cfg.dataDir}/storage/app".d = defaultConfig;
      "${cfg.dataDir}/storage/fonts".d = defaultConfig;
      "${cfg.dataDir}/storage/framework".d = defaultConfig;
      "${cfg.dataDir}/storage/framework/cache".d = defaultConfig;
      "${cfg.dataDir}/storage/framework/sessions".d = defaultConfig;
      "${cfg.dataDir}/storage/framework/views".d = defaultConfig;
      "${cfg.dataDir}/storage/logs".d = defaultConfig;
      "${cfg.dataDir}/storage/uploads".d = defaultConfig;
      "${cfg.dataDir}/bootstrap/cache".d = defaultConfig;
    };

    users = {
      users = mkIf (user == "speedtest-tracker") {
        speedtest-tracker = {
          inherit group;
          isSystemUser = true;
        };
        "${config.services.nginx.user}".extraGroups = [ group ];
      };
      groups = mkIf (group == "speedtest-tracker") {
        speedtest-tracker = {};
      };
    };

  };

  meta.maintainers = with maintainers; [ 3u13r ];
}