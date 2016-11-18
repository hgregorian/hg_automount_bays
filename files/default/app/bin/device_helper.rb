#!/bin/env ruby

require 'fileutils'
require 'logger'
require 'mixlib/shellout'
require 'open3'
require 'optparse'
require 'yaml'

DRY_RUN = false

## Setup some init variables
program_name = File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))

config_path = File.join(__dir__, '../etc', "#{program_name}.yml")
@log = Logger.new(File.join(__dir__, '../var/log', "#{program_name}.log"))
app_config = YAML.load_file(config_path)
@options = app_config.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }

def logger(sev, msg, fatal = false)
  @log.send(sev, msg)
  puts msg if fatal
end

def sanitize_key(string)
  string.downcase!
  # string.gsub!(/\(.*/, '')
  string.gsub!(/[^a-z\s].*/, '')
  string.gsub!(/[^a-z\s]/, '')
  string.strip!
  string.gsub!(/\s/, '_')
  string.to_sym
end

def hba_info
  ## Split stdout into device sections
  result = run_command('/usr/local/sbin/sas3ircu 0 display', true)
  sections = result.scan(/^Device.*?\n(.*?)(?:\n\n|\n---*?)/m).flatten.map { |x| x.split("\n") }
  logger(:debug, "Saw #{sections.length} sections")

  ## Break individual entries in sections into key/value pairs
  sections.map! do |section|
    Hash[*section.map do |entry|
      kv_pairs = entry.split(':').map(&:strip)
      kv_pairs[0] = sanitize_key(kv_pairs[0])
      kv_pairs
    end.flatten]
  end

  ## Manipulate a couple of fields
  sections.each do |section|
    ## Sanitize drive "state" flag
    section[:state] = section[:state].match(/\((.*?)\)/)[1]

    ## Provide a reasonable physical bay ID (1-24, left to right, top to bottom)
    section[:bay_id] = (1..@options[:number_of_bays]).to_a.each_slice(4).to_a.map(&:reverse).flatten[section[:slot].to_i]
  end

  ## Provide hash with GUIDs (WWN/WWID) as keys
  Hash[sections.map { |section| [section[:guid], section] }]
end

def run_command(cmd, abort_on_error = false)
  cmd = command.join(' ') if cmd.is_a?(Array)
  begin
    result = Mixlib::ShellOut.new(cmd).run_command
  rescue => e
    logger(:error, "Error running command #{cmd} - #{e}", true)
    exit(1)
  end
  if result.error?
    logger(:error, "Error running command #{cmd}", true)
    exit(1) if abort_on_error
  end
  result.stdout
end

def parity_bay?(bay)
  @options[:parity_bays].include? bay.to_i
end

def mergerfs_ctl(cmd)
  return unless @options[:mergerfs_support]
  run_command(cmd)
end

def zero_padding(num, padding)
  num.to_s.rjust(padding.to_i, '0')
end

def blkid_attrs(bay_id)
  result = run_command("/sbin/blkid -o udev -p /dev/disk/by-bay/#{bay_id}")
  Hash[*result.split("\n").map { |x| x.split('=') }.flatten]
end

def wwn_lookup(dev)
  result = run_command("/lib/udev/scsi_id -g /dev/#{dev}", true)
  wwn = result.chomp[1..-1]
  logger(:debug, "WWN for #{dev}: #{wwn}")
  wwn
end

begin
  opts = OptionParser.new do |o|
    o.banner = "Usage: #{program_name} [--add|--remove] [options]"
    o.separator 'Mandatory flags:'
    o.on('-a', '--add BAY_ID', String,
         "ex. '15'") do |opt|
      @options[:add] = opt.to_i
    end
    o.on('-r', '--remove BAY_ID', String,
         "ex. '15'") do |opt|
      @options[:remove] = opt.to_i
    end
    o.parse!(ARGV)
  end
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  puts $ERROR_INFO.to_s
  puts opts
  exit(1)
end

logger(:debug, "Called with options #{@options}")
logger(:debug, "ARGV[0] == #{ARGV[0]}")

if ARGV[0] =~ /^sd[a-z]+$/
  dev = ARGV[0]
  logger(:info, "Looking up information for #{dev}")

  result = hba_info[wwn_lookup(dev)]

  ## Print environment variables for use with udev
  if result
    logger(:info, "Result found for #{dev}")
    result.each do |k, v|
      value = v =~ /\s/ ? "'#{v}'" : v
      str = "#{k.upcase}=#{value}"
      puts str
      logger(:debug, str)
    end
    exit(0)
  else
    logger(:warn, "No result found for #{dev}; not managed by HBA", true)
    exit(1)
  end
end

if @options[:add]
  ## Store bay_id
  bay_id = @options[:add]

  logger(:info, "Adding drive in bay ID #{bay_id}")

  ## Abort if the bay_id is not present as 'by-bay' symlink (very improbable)
  unless File.exist?("/dev/disk/by-bay/#{bay_id}")
    logger(:error, "Nothing found in bay '#{bay_id}'...", true)
    exit(1)
  end

  ## Check formatting
  if blkid_attrs(bay_id)['ID_FS_TYPE'] != 'ext4'
    logger(:warn, "Drive in bay #{bay_id} not formatted correctly")
    if @options[:auto_format]
      logger(:info, "Formatting bay #{bay_id}")
      run_command("/usr/sbin/mkfs.ext4 -F -m 0 '/dev/disk/by-bay/#{bay_id}'")
    end
  end

  ## Define mount point based on whether or not it has been designated as a parity bay
  mount_point = if parity_bay?(bay_id)
                  File.join(@options[:mount_root], "#{zero_padding(bay_id, 2)}-#{@options[:suffix_parity]}")
                else
                  File.join(@options[:mount_root], "#{zero_padding(bay_id, 2)}-#{@options[:suffix_data]}")
                end

  ## Create mount point and mount
  FileUtils.mkdir_p(mount_point)
  run_command("/usr/bin/mount #{mount_point}")

  ## Add to merger volume if not in a parity bay
  mergerfs_ctl("/usr/local/sbin/mergerfs.ctl -m /storage add path #{mount_point}") unless parity_bay?(bay_id)
end

if @options[:remove]
  ## Pad bay_id with 0, i.e. 3 => 03, 20 => 20, etc.
  bay_id = zero_padding(@options[:remove], 2)

  ## Since it doesn't matter if this is a parity or data bay, look for either
  dirs = Dir.glob(File.join(@options[:mount_root], "#{bay_id}-*"))

  ## Something is horribly wrong if a bay_id matches multiples (implies that mount points exist for both parity and data)
  abort "Too many matches for removal! #{dirs}" if dirs.length > 1

  ## Store single match as mount point
  mount_point = dirs[0]

  ## This is precautionary as there's no reason to believe, at this time,
  ## that a bay_id, designated for parity, could've been mounted as a data mount
  mergerfs_mount_point = File.join(@options[:mount_root], "#{bay_id}-#{@options[:suffix_data]}")
  mergerfs_ctl("/usr/local/sbin/mergerfs.ctl -m /storage remove path #{mergerfs_mount_point}")

  ## Unmount and clean-up mount point
  unless mount_point.empty?
    run_command("/usr/bin/umount -l #{mount_point}")
    FileUtils.rm_rf(mount_point)
  end
end

exit(0)
