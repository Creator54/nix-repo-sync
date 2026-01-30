{ pkgs, lib }:

{ user, syncItems }:

let
  # Generate the main sync script
  syncScript = pkgs.writeShellScript "nix-repo-sync.sh" ''
    LOG_FILE="/var/log/nix-repo-sync.log"
    mkdir -p /var/log
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    }

    log "INFO: Starting sync cycle"
    
    SYNC_FAILED=0
    
    ${lib.concatMapStringsSep "\n" (item:
      if item.type == "git" then ''
        # Git sync for ${item.dest}
        log "INFO: Processing git sync: ${item.source} -> ${item.dest}"
        DEST="${item.dest}"
        # Expand tilde to home directory
        DEST="''${DEST/#\~/$HOME}"
        
        mkdir -p "$(dirname "$DEST")"
        
        if [ ! -d "$DEST/.git" ]; then
          log "INFO: Cloning ${item.source} to $DEST"
          if ${pkgs.git}/bin/git clone "${item.source}" "$DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS: Git clone completed for $DEST"
            ${if item.postSync != null then ''
              log "INFO: Running post-sync command for $DEST"
              cd "$DEST"
              if ${item.postSync} >> "$LOG_FILE" 2>&1; then
                log "SUCCESS: Post-sync command succeeded"
              else
                log "ERROR: Post-sync command failed"
                SYNC_FAILED=1
              fi
            '' else ""}
          else
            log "ERROR: Git clone failed for $DEST with exit code $?"
            SYNC_FAILED=1
          fi
        else
          log "INFO: Pulling latest changes for $DEST"
          cd "$DEST"
          # Only run post-sync if there were updates or if it's forced (currently always runs on pull)
          if ${pkgs.git}/bin/git pull --ff-only 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS: Git pull completed for $DEST"
            ${if item.postSync != null then ''
              log "INFO: Running post-sync command for $DEST"
              if ${item.postSync} >> "$LOG_FILE" 2>&1; then
                log "SUCCESS: Post-sync command succeeded"
              else
                log "ERROR: Post-sync command failed"
                SYNC_FAILED=1
              fi
            '' else ""}
          else
            log "ERROR: Git pull failed for $DEST with exit code $?"
            SYNC_FAILED=1
          fi
        fi
      ''
      else if item.type == "local" then ''
        # Local symlink sync for ${item.dest}
        log "INFO: Processing local sync: ${item.source} -> ${item.dest}"
        # Expand tilde to home directory
        SOURCE="${item.source}"
        SOURCE="''${SOURCE/#\~/$HOME}"
        DEST="${item.dest}"
        # Expand tilde to home directory
        DEST="''${DEST/#\~/$HOME}"
        
        if [ ! -e "$SOURCE" ]; then
          log "ERROR: Source path does not exist: $SOURCE"
          SYNC_FAILED=1
        elif [ -L "$DEST" ]; then
          # Symlink already exists, check if it points to the right place
          CURRENT_TARGET=$(readlink "$DEST")
          if [ "$CURRENT_TARGET" = "$SOURCE" ]; then
            log "INFO: Symlink already correct at $DEST"
          else
            log "INFO: Updating symlink at $DEST to point to $SOURCE"
            rm "$DEST"
            ln -sf "$SOURCE" "$DEST"
            log "SUCCESS: Symlink updated: $DEST -> $SOURCE"
          fi
        elif [ -e "$DEST" ]; then
          log "WARNING: Removing existing file/directory at $DEST to create symlink"
          rm -rf "$DEST"
          mkdir -p "$(dirname "$DEST")"
          if ln -sf "$SOURCE" "$DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS: Symlink created: $DEST -> $SOURCE"
            ${if item.postSync != null then ''
              log "INFO: Running post-sync command for $DEST"
              if ${item.postSync} >> "$LOG_FILE" 2>&1; then
                log "SUCCESS: Post-sync command succeeded"
              else
                log "ERROR: Post-sync command failed"
                SYNC_FAILED=1
              fi
            '' else ""}
          else
            log "ERROR: Failed to create symlink: $DEST -> $SOURCE"
            SYNC_FAILED=1
          fi
        else
          mkdir -p "$(dirname "$DEST")"
          if ln -sf "$SOURCE" "$DEST" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS: Symlink created: $DEST -> $SOURCE"
            ${if item.postSync != null then ''
              log "INFO: Running post-sync command for $DEST"
              if ${item.postSync} >> "$LOG_FILE" 2>&1; then
                log "SUCCESS: Post-sync command succeeded"
              else
                log "ERROR: Post-sync command failed"
                SYNC_FAILED=1
              fi
            '' else ""}
          else
            log "ERROR: Failed to create symlink: $DEST -> $SOURCE"
            SYNC_FAILED=1
          fi
        fi
      ''
      else ''
        log "ERROR: Unknown sync type: ${item.type}"
        SYNC_FAILED=1
      ''
    ) syncItems}
    
    log "INFO: Sync cycle completed"
    exit $SYNC_FAILED
  '';

  # Generate force sync utility
  forceSyncScript = pkgs.writeShellScriptBin "nix-repo-sync-force" ''
    echo "Triggering immediate sync..."
    sudo systemctl restart nix-repo-sync.service
    echo ""
    echo "Service status:"
    sudo systemctl status nix-repo-sync.service --no-pager
  '';

  # Generate log viewer utility
  logViewerScript = pkgs.writeShellScriptBin "nix-repo-sync-logs" ''
    LINES=''${1:-100}
    if [ -f /var/log/nix-repo-sync.log ]; then
      tail -n "$LINES" /var/log/nix-repo-sync.log
    else
      echo "Log file not found: /var/log/nix-repo-sync.log"
      exit 1
    fi
  '';

in
{
  # Systemd service configuration
  service = {
    description = "Configuration Sync Service";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    
    path = with pkgs; [
      nix
      git
      openssh
      coreutils
      findutils
      gnugrep
      gnused
      systemd
    ];
    
    serviceConfig = {
      Type = "oneshot";
      User = user;
      ExecStart = "${syncScript}";
      StandardOutput = "append:/var/log/nix-repo-sync.log";
      StandardError = "append:/var/log/nix-repo-sync.log";
    };
  };

  # Systemd timer configuration
  timer = {
    description = "Nix Repository Sync Timer (Hourly)";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };

  # CLI utility scripts
  scripts = {
    force = forceSyncScript;
    logs = logViewerScript;
  };
}
