#!/bin/env ruby

abort 'No DEVNAMES (paths) provided, exiting.' unless ARGV[0]

bay_paths = ARGV[0].split.grep(/by-bay/)
abort "More than one 'bay path' returned!? #{bay_path}" if bay_paths.length > 1
bay_id = bay_paths[0].split('/')[-1]
puts "BAY_ID=#{bay_id}"
exit(0)
