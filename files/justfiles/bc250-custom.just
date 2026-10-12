# Read-only hardware, services, and temperature report
bc250-diagnostics:
    @bc250-diag

# Read-only RAM, ZRAM, disk swap, and memory-pressure report
bc250-memory-status:
    @bc250-memory status

# Create or re-enable an optional 8 GiB disk swapfile (preserves ZRAM)
bc250-setup-swap:
    @sudo bc250-memory setup

# Disable managed disk swap without deleting its file
bc250-disable-swap:
    @sudo bc250-memory disable

# Enable automatic full 40CU dispatch and apply it now
bc250-enable-40cu-boot:
    @sudo systemctl unmask bc250-force-40cu.service
    @sudo systemctl enable --now bc250-force-40cu.service

# Disable both boot unlock paths and restore driver dispatch
bc250-recover-stock:
    @sudo systemctl mask --now bc250-force-40cu.service
    @sudo bc250-cu-live-manager uninstall-service
    @sudo bc250-cu-live-manager --yes stock-dispatch

# Show automatic unlock results from the current boot
bc250-unlock-logs:
    @journalctl -b -u bc250-force-40cu.service --no-pager

# Compare stock and patched Vulkan compute-queue availability
bc250-async-status:
    @bc250-async-compute status

# Run the upstream async compute correctness tests
bc250-async-test:
    @bc250-async-compute test

# Restore stock Vulkan driver selection after logout/reboot
bc250-async-disable:
    @sudo bc250-async-compute always disable

# Enable the private patched Vulkan driver after logout/reboot
bc250-async-enable:
    @sudo bc250-async-compute always enable

# Show the game benchmark recorder's options
bc250-benchmark-help:
    @bc250-benchmark run --help

# List saved before/after game benchmark runs
bc250-benchmark-list:
    @bc250-benchmark list
