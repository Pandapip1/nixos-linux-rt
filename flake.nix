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
          rtKernels = lib.mapAttrs (_: mkRtKernel) pkgs.linuxKernel.kernels;
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
