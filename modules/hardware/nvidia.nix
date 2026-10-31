{ config, pkgs, ... }:
{
  # NVIDIA, Turing or newer (fox-blue's RTX 2060 Super). The open kernel
  # module is what NVIDIA recommends from Turing on.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = true;
    modesetting.enable = true;    # required for Wayland
    # Saves video memory across sleep. fox-blue never sleeps, but this keeps
    # a manual suspend from coming back to a corrupted screen.
    powerManagement.enable = true;
    nvidiaSettings = false;        # X11 tool; nothing to configure under Wayland
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Early KMS: load the driver in the initrd, so it owns the display before
  # the login manager (greetd) starts. Without it, the automatic login can
  # start Hyprland while the driver is still loading, and Hyprland exits at
  # once. (Seen with SDDM before greetd; the race is the same.)
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  # VA-API (hardware video decode) on top of NVDEC, for browsers and mpv/VLC.
  hardware.graphics.extraPackages = [ pkgs.nvidia-vaapi-driver ];

  fox.desktop.hyprlandEnv = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";        # nvidia-vaapi-driver's recommended backend
  };

  # Sandboxed apps (nixpak) only get /dev/dri and /run/opengl-driver by
  # default, which is enough for Mesa. For drawing to Wayland windows the
  # NVIDIA driver loads egl-wayland from a list it normally finds at
  # /etc/egl/egl_external_platform.d. On NixOS that's a link through
  # /etc/static, which the sandboxes can't follow, so EGL on Wayland fell
  # back to Mesa's llvmpipe and Minecraft in Prism drew on the CPU. The same
  # list is in /run/opengl-driver, which they do get; point the driver there.
  fox.desktop.sandboxGpuEnv = {
    __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS = "/run/opengl-driver/share/egl/egl_external_platform.d";
    # GLFW over EGL (Minecraft's window on Wayland: the sandboxes have no
    # X11) fails on NVIDIA with "GLFW error 65544: EGL: Failed to clear
    # current context" unless the driver's threaded optimizations are off.
    # https://wiki.nixos.org/wiki/Minecraft
    __GL_THREADED_OPTIMIZATIONS = "0";
  };

  # The NVIDIA driver also talks through these device nodes.
  fox.desktop.sandboxGpuDevices = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-modeset"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
  ];
}
