{
  nixConfig = {
    extra-substituters = [
      "https://nixos.cache.pandapip1.com/nixos-linux-rt"
    ];
    extra-trusted-public-keys = [
      "nixos-linux-rt:v8hi9bTm2fwCfChJgKLJw2xar8nBvqDKfyuMGfk/gfY="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.platforms.linux;

      perSystem =
        {
          pkgs,
          system,
          self',
          ...
        }:
        let
          isSafeKernel =
            drv:
            let
              intermediate = lib.tryEval (lib.isDerivation drv && lib.versionAtLeast drv.version "6.12"); # PREEMPT_RT merged into mainline in 6.12
            in
            intermediate.success && intermediate.value;
          mkRtKernel =
            baseKernel:
            baseKernel.override (originalArgs: {
              argsOverride = {
                version = "${baseKernel.version}-rt";
                modDirVersion = baseKernel.modDirVersion or baseKernel.version;
              };
              structuredExtraConfig =
                with lib.kernel;
                {
                  EXPERT = yes;
                  PREEMPT_RT = yes;
                  # i915 GVT is incompatible with PREEMPT_RT
                  # https://lists.freedesktop.org/archives/intel-gfx/2022-February/289691.html
                  DRM_I915_GVT = lib.mkForce unset;
                  DRM_I915_GVT_KVMGT = lib.mkForce unset;
                }
                // (lib.optionalAttrs (lib.versionAtLeast baseKernel.version "6.12" && lib.versionOlder baseKernel.version "6.13") {
                  # Fix error: option not set correctly: PREEMPT_VOLUNTARY (wanted 'y', got 'n').
                  PREEMPT_VOLUNTARY = lib.mkForce no; # PREEMPT_RT and PREEMPT_VOLUNTARY are incompatible
                });
            });

          upstreamKernels = pkgs.linuxKernel.kernels;
          safeKernels = lib.filterAttrs (_: isSafeKernel) upstreamKernels;
          rtKernels = lib.mapAttrs (_: mkRtKernel) safeKernels;
          rtPackages = lib.mapAttrs (_: pkgs.linuxPackagesFor) rtKernels;
        in
        {
          legacyPackages = {
            inherit mkRtKernel;
            kernels = rtKernels;
            packages = rtPackages;
          };
        };
    };
}
