# 0.4.4
- use mergerfs 2.19.0, add options 'use_ino' and 'direct_io'

# 0.4.3
- use mergerfs 2.18.0, change pool policy to non-path preserving

# 0.4.1
- use `hg_mergerfs` resources and remove attribute references (there's no functional difference here)

# 0.4.0
- added missing package dependency (ruby) and appropriate gem install (both needed for `device_helper`)
- excerpted mergerfs support into its own recipe and provided a "dummy" read-only srcmount (see inline notes in this recipe)
- reordered recipe inclusions to combat some terrible assumptions made earlier

# 0.3.0
- reworked udev rules
- logging for all `device_helper.rb` actions
- documentation improvements

# 0.2.0
- in `device_helper.rb`, depending on symlinks in `/dev/disk` was a horrible idea; now sourcing WWN/WWID's using a more reliable method
- minor tweak to udev rule
- determine if device is eligable to be mounted based on formatting; remediate if desired

# 0.1.0
Initial release

# 0.0.0

Initial creation of hg_automount_bays
