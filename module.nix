{ config, lib, pkgs, ... }:

let
  cfg = config.services."nix-repo-sync";
  
  # Import the library function
  mkConfigSync = import ./lib.nix { inherit pkgs lib; };
  
  # Generate sync configuration
  syncConfig = mkConfigSync {
    user = cfg.user;
    syncItems = cfg.syncItems;
  };

in
{
  options.services."nix-repo-sync" = {
    enable = lib.mkEnableOption "Nix repository sync service";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.users.users.${builtins.head (builtins.attrNames config.users.users)}.name or "root";
      description = "User to run the sync service as";
      example = "creator54";
    };

    syncItems = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.enum [ "git" "local" ];
            description = ''
              Type of sync operation:
              - "git": Clone/pull from a git repository (one-way sync)
              - "local": Create symlink to local directory (bi-directional)
            '';
            example = "git";
          };

          source = lib.mkOption {
            type = lib.types.str;
            description = "Source path - either a git repository URL or a local path";
            example = "https://github.com/user/nvim-configs or /home/user/local-configs";
          };

          dest = lib.mkOption {
            type = lib.types.str;
            description = "Destination path (supports ~ for home directory)";
            example = "~/.config/nvim";
          };
        };
      });
      default = [];
      description = ''
        List of items to sync. Each item can be either a git repository
        or a local directory symlink.
      '';
      example = lib.literalExpression ''
        [
          {
            type = "git";
            source = "https://github.com/Creator54/starter.git";
            dest = "~/.config/nvim";
          }
          {
            type = "local";
            source = "/home/user/nix-systems/modules/essential/configs/common/fish";
            dest = "~/.config/fish";
          }
        ]
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Install systemd service (runs periodically via timer)
    systemd.services."nix-repo-sync" = syncConfig.service;

    # Install systemd timer
    systemd.timers."nix-repo-sync" = syncConfig.timer;
    
    # Run nix-repo-sync during system activation (before Home Manager)
    # This ensures configs are cleaned up and symlinked before HM tries to manage them
    system.activationScripts.nixRepoSyncPreActivation = lib.stringAfter [ "users" ] ''
      echo "Running nix-repo-sync to prepare configs..."
      # Ensure log file exists with correct permissions before running sync
      mkdir -p /var/log
      touch /var/log/nix-repo-sync.log || true
      chown ${cfg.user}:users /var/log/nix-repo-sync.log || true
      chmod 0644 /var/log/nix-repo-sync.log || true
      ${pkgs.sudo}/bin/sudo -u ${cfg.user} ${syncConfig.service.serviceConfig.ExecStart} || true
    '';
    
    # Install CLI utilities
    environment.systemPackages = [
      syncConfig.scripts.force
      syncConfig.scripts.logs
    ];
    
    # Ensure log directory and /var/www exist with proper permissions
    systemd.tmpfiles.rules = [
      "d /var/log 0755 root root -"
      "f /var/log/nix-repo-sync.log 0644 ${cfg.user} users -"
      "d /var/www 0755 ${cfg.user} users -"
    ];

    # Configure log rotation
    services.logrotate = {
      enable = true;
      settings = {
        "/var/log/nix-repo-sync.log" = {
          frequency = "daily";
          rotate = 3;
          size = "10M";
          compress = true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          create = "0644 ${cfg.user} users";
        };
      };
    };
  };
}
