{
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
          upstreamKernels = pkgs.linuxKernel.kernels;
          isSafeKernel =
            drv:
            let
              intermediate = lib.tryEval (lib.isDerivation drv && lib.versionAtLeast drv.version "6.12"); # PREEMPT_RT merged into mainline in 6.12
            in
            intermediate.success && intermediate.value;
          safeKernelNames = lib.attrNames (lib.filterAttrs (_: isSafeKernel) upstreamKernels);
          mkRtKernel =
            baseKernel:
            baseKernel.override (originalArgs: {
              argsOverride = {
                version = "${baseKernel.version}-rt";
                modDirVersion = baseKernel.modDirVersion or baseKernel.version;
              };
              structuredExtraConfig = with lib.kernel; {
                EXPERT = yes;
                PREEMPT_RT = yes;
                # Incompatible with PREEMPT_RT
                DRM_I915_GVT = lib.mkForce unset;
                DRM_I915_GVT_KVMGT = lib.mkForce unset;
              };
            });
          rtKernels = lib.genAttrs safeKernelNames (name: mkRtKernel upstreamKernels.${name});
          rtPackages = lib.mapAttrs (_: pkgs.linuxPackagesFor) rtKernels;
        in
        {
          legacyPackages = {
            inherit mkRtKernel safeKernelNames;
            kernels = rtKernels;
            packages = rtPackages;
          };
        };
    };
}
