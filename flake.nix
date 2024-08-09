{
  inputs = rec {
    nixpkgs.url = "github:NixOS/nixpkgs/release-24.05";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    zig = inputs.zig-overlay.packages.x86_64-linux.master-2024-08-07;
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        zig
        lldb
        vulkan-loader
        glfw
        xorg.libX11
        xorg.libXrandr
      ];
    };
  };
}
