{ inputs, config, lib, pkgs, modulesPath, ... }:

with builtins;

let
  domain = "lists.htlwienwest-alumni.at";
  subdomain = name: name + "." + domain;
  localMail = localPart: "${localPart}@${domain}";
  dnsProvider = "cloudflare";
  me = rec {
    name = "Lorenz Leutgeb";
    username = "lorenz.leutgeb";
    email = "${username}@htlwienwest-alumni.at";
  };
in {
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    "${modulesPath}/virtualisation/qemu-guest-agent.nix"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  boot = {
    growPartition = true;
    kernelParams = [ "console=ttyS0" ];
    kernel.sysctl."net.ipv4.ip_forward" = 1;
    initrd = {
      availableKernelModules = [ ];
      kernelModules = [ ];
    };
    kernelModules = [ ];
    loader = {
      grub = {
        enable = true;
        device = "/dev/vda";
      };
      timeout = 5;
    };
  };

  nix.settings.max-jobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

  networking = {
    hostName = "nc";
    defaultGateway = "193.26.156.1";
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "193.26.158.210";
        prefixLength = 22;
      }];
      ipv6.addresses = [{
        address = "2a03:4000:4c:f5d::";
        prefixLength = 64;
      }];
    };
  };

  time.timeZone = "Europe/Vienna";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    binutils
    coreutils
    exfat
    fuse
    lsof
    nixFlakes
    pflogsumm
    utillinux
    vim
    wget
    which
    zip
  ];

  networking.firewall.allowedTCPPorts = [
    22 # sshd
    25 # postfix (SMTP)
    80 # nginx
    443 # nginx
    465 # dovecot/postfix ? (SMTP over TLS)
    993 # dovecot (IMAP over TLS)
  ];

  systemd = {
    services = { systemd-resolved.enable = true; };
    network = {
      enable = true;
      networks."eth0" = {
        enable = true;
        matchConfig.Name = "eth0";
        dns = [ "1.1.1.1" ];
        domains = [ ];
        address = [ "193.26.158.210/22" "2a03:4000:4c:f5d::/64" ];
        routes = [{ routeConfig.Gateway = "193.26.156.1"; }];
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };

  services = {
    opendkim = {
      enable = true;
      domains = "csl:${domain}";
      selector = "lists0";
    };

    uwsgi.enable = true;

    qemuGuest.enable = true;

    resolved = {
      enable = true;
      extraConfig = ''
        DNSOverTLS= yes
      '';
    };

    postfix = {
      enable = true;
      relayDomains = [ "hash:/var/lib/mailman/data/postfix_domains" ];
      sslCert = config.security.acme.certs.${domain}.directory + "/full.pem";
      sslKey = config.security.acme.certs.${domain}.directory + "/key.pem";
      config = {
        transport_maps = [ "hash:/var/lib/mailman/data/postfix_lmtp" ];
        local_recipient_maps = [ "hash:/var/lib/mailman/data/postfix_lmtp" ];
        default_language = "de";

        milter_protcol = "6";
        smtpd_milters = "unix:/run/opendkim/opendkim.sock";
        non_smtpd_milters = "unix:/run/opendkim/opendkim.sock";
      };
    };

    mailman = {
      enable = true;
      hyperkitty.enable = true;
      serve.enable = true;
      siteOwner = me.email;
      webUser = config.services.uwsgi.user;
      webHosts = [ domain ];
      webSettings = {
        SITE_ID = 2;
        TIME_ZONE = "Europe/Vienna";
        DEFAULT_FROM_EMAIL = localMail "mailman";
        SERVER_EMAIL = localMail "mailman";
      };
    };

    openssh = { enable = true; };

    nginx = {
      enable = true;
      virtualHosts = {
        "${domain}" = {
          serverAliases = [
            (subdomain "www")
            (subdomain "mta-sts")
            (subdomain "autoconfig")
          ];
          onlySSL = true;
          enableACME = false;
          useACMEHost = "${domain}";
          locations."/" = { root = "/var/www"; };
        };
      };
    };
  };

  home-manager.users.${me.username}.imports = [
    "${inputs.lorenz}/hm/profiles/terminal.nix"
    "${inputs.vscode-server}/modules/vscode-server/home.nix"
  ];

  users.users.${me.username} = {
    isNormalUser = true;
    createHome = true;
    home = "/home/${me.username}";
    description = me.name;
    extraGroups = [ "disk" "docker" "wheel" ];
    uid = 1000;
    shell = pkgs.zsh;
    hashedPassword =
      "$6$rJZSLnQH1hInB93$lfi4c2zxQbSJV7H9T9lrjOj6WIDhSEqP5FyjMinEE44j81E1l57hF6Epyxb02EbcWqDT9eYbyo4dBTAwewBgQ/";
  };
  users.mutableUsers = false;
  users.users."nginx".extraGroups = [ "acme" ];
  users.users."postfix".extraGroups = [ "acme" ];

  programs = {
    ssh.startAgent = true;
    zsh.enable = true;
  };

  security = {
    sudo.wheelNeedsPassword = false;
    acme = {
      defaults.email = me.email;
      acceptTerms = true;
      certs =
        let credentialsFile = "/home/${me.username}/.config/lego/cloudflare";
        in {
          "${domain}" = {
            inherit (me) email;
            inherit dnsProvider credentialsFile;
          };
          "${domain}-wildcard" = {
            inherit (me) email;
            inherit dnsProvider credentialsFile;
            domain = subdomain "*";
          };
        };
    };
  };

  nixpkgs.config.allowUnfree = true;

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = "experimental-features = nix-command flakes";
  };
}
