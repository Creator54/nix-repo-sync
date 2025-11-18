# nix-repo-sync

NixOS module for syncing git repositories and creating configuration symlinks. Keeps configs editable outside `/nix/store` while maintaining declarative management.

- Git sync: Clone/pull repositories automatically
- Local symlinks: Bidirectional sync for editable configs  
- Automatic scheduling: Runs on boot, hourly, and during system activation

> **Note:** This is an impure solution - synced content is not tracked by Nix and has no hash verification. Use for configs you need to edit frequently.

## Installation

Add to your `flake.nix`:

```nix
{
  inputs.nix-repo-sync = {
    url = "github:Creator54/nix-repo-sync";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-repo-sync, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [ nix-repo-sync.nixosModules.default ];
    };
  };
}
```

## Basic Usage

```nix
{
  services."nix-repo-sync" = {
    enable = true;
    user = "username";  # User who will own the synced files/symlinks
    syncItems = [
      # Git: one-way sync from remote
      {
        type = "git";
        source = "https://github.com/user/nvim-config";
        dest = "~/.config/nvim";
      }
      # Local: bidirectional symlink
      {
        type = "local";
        source = "/path/to/configs/fish";
        dest = "~/.config/fish";
      }
    ];
  };
}
```

## Using Dynamic Paths (Optional)

To symlink configs from your editable repository, pass `flakeRoot`:

```nix
# flake.nix
{
  outputs = { self, nixpkgs, nix-repo-sync, ... }:
    let
      flakeRoot = builtins.getEnv "PWD";
    in {
      nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit flakeRoot; };
        modules = [ nix-repo-sync.nixosModules.default ];
      };
    };
}

# configuration.nix
{ flakeRoot, ... }:
{
  services."nix-repo-sync".syncItems = [
    {
      type = "local";
      source = "${flakeRoot}/configs/fish";
      dest = "~/.config/fish";
    }
  ];
}
```

**Requires `--impure` flag:**
```bash
sudo nixos-rebuild switch --flake .#hostname --impure
```

## Options

- `enable`: Enable the service (default: `false`)
- `user`: User who will own synced files and run the service (default: first user or `root`)
- `syncItems`: List of sync items with:
  - `type`: `"git"` (clone/pull) or `"local"` (symlink)
  - `source`: Git URL or local path
  - `dest`: Destination path (supports `~` for user's home)

## CLI Commands

```bash
nix-repo-sync-force      # Trigger immediate sync
nix-repo-sync-logs       # View last 100 lines
nix-repo-sync-logs 50    # View last 50 lines
```

Logs: `/var/log/nix-repo-sync.log`

## How It Works

- **On boot**: Syncs 5 minutes after startup
- **Hourly**: Automatic sync via systemd timer
- **On rebuild**: Runs during system activation (before Home Manager)
