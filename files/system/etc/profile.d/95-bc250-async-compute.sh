# Match the graphical session's private Vulkan driver selection for login shells.
export VK_DRIVER_FILES=/usr/lib/bc250-radv/share/vulkan/icd.d/radeon_icd.x86_64.json:/usr/share/vulkan/icd.d/radeon_icd.i686.json:/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
