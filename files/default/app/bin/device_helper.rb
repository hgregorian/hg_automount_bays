#!/bin/env ruby

require 'fileutils'
require 'logger'
require 'mixlib/shellout'
require 'open3'
require 'optparse'
require 'yaml'

## Setup some init variables
program_name = File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))

config_path = File.join(__dir__, '../etc', "#{program_name}.yml")
app_config = YAML.load_file(config_path)
@options = app_config.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }

@log = Logger.new(File.join(__dir__, '../var/log', "#{program_name}.log"))
@log.level = Logger.const_get(@options[:log_level].to_s.upcase)

def logger(sev, msg, fatal = false)
  @log.send(sev, msg)
  puts msg if fatal
end

def sanitize_key(string)
  ## normalize case
  string.downcase!
  ## remove non-alpha/whitespace and everything after
  string.gsub!(/[^a-z\s].*/, '')
  ## trim leading and trailing whitespace
  string.strip!
  ## replace whitespace with underscore
  string.gsub!(/\s/, '_')
  ## return as symbol
  string.to_sym
end

def hba_info
  ## Split stdout into device sections
  result = run_command('/usr/local/sbin/sas3ircu 0 display', true)
  sections = result.scan(/^Device.*?\n(.*?)(?:\n\n|\n---*?)/m).flatten.map { |x| x.split("\n") }
  logger(:debug, "HBA info returned #{sections.length} sections")

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
    bay_id = (1..@options[:number_of_bays]).to_a.each_slice(4).to_a.map(&:reverse).flatten[section[:slot].to_i]
    section[:bay_id] = bay_id.to_s.rjust(2, '0')
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

def parity_bay?(bay_id)
  @options[:parity_bays].map(&:to_i).include? bay_id.to_i
end

def mergerfs_modify_pool(action, filesystem, srcmount)
  return unless @options[:mergerfs_support]

  srcmount_matches = run_command('/usr/local/sbin/mergerfs.ctl info').split.grep(/^#{srcmount}$/)

  case action
  when :add
    logger(:info, "#{action.capitalize} #{srcmount} to mergerfs filesystem '#{filesystem}'")
    if srcmount_matches.empty?
      run_command("/usr/local/sbin/mergerfs.ctl -m #{filesystem} add path #{srcmount}")
    else
      logger(:error, "#{srcmount} already in mergerfs filesystem '#{filesystem}'")
    end
  when :remove
    logger(:info, "#{action.capitalize} #{srcmount} from mergerfs filesystem '#{filesystem}'")
    if srcmount_matches.empty?
      logger(:error, "#{srcmount} not present in mergerfs filesystem '#{filesystem}'")
    else
      srcmount_matches.each do |m|
        run_command("/usr/local/sbin/mergerfs.ctl -m #{filesystem} remove path #{m}")
      end
    end
  end
end

def blkid_attrs(bay_id)
  result = run_command("/sbin/blkid -o udev -p /dev/disk/by-bay/#{bay_id}")
  Hash[*result.split("\n").map { |x| x.split('=') }.flatten]
end

def wwn_lookup(dev)
  result = run_command("/lib/udev/scsi_id -g /dev/#{dev}", false)
  wwn = result.chomp[1..-1]
  logger(:debug, "WWN for #{dev}: #{wwn}")
  wwn
end

def mounted?(mount_point)
  !File.readlines('/proc/mounts').grep(/#{mount_point}/).empty?
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
logger(:debug, "Called with args #{ARGV}")

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
  else
    logger(:warn, "No result found for #{dev}; not managed by HBA", true)
  end
  exit(0)
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
                  File.join(@options[:mount_root], "#{bay_id}-#{@options[:suffix_parity]}")
                else
                  File.join(@options[:mount_root], "#{bay_id}-#{@options[:suffix_data]}")
                end

  if mounted?(mount_point)
    logger(:info, "#{mount_point} already mounted")
  else
    ## Create mount point and mount
    FileUtils.mkdir_p(mount_point)
    run_command("/usr/bin/mount #{mount_point}")
    logger(:info, "Mounted #{bay_id} at #{mount_point}")
  end

  ## Add to merger volume if not in a parity bay
  mergerfs_modify_pool(:add, '/storage', mount_point) unless parity_bay?(bay_id)
end

if @options[:remove]
  bay_id = @options[:remove]

  logger(:info, "Removing drive in bay ID #{bay_id}")

  ## Determine mount point from /proc/mounts
  mount_point = begin
                  File.readlines('/proc/mounts').grep(/#{File.join(@options[:mount_root], bay_id)}/)[0].split[1]
                rescue
                  Dir.glob(File.join(@options[:mount_root], "#{bay_id}-*"))[0]
                end

  ## Remove mount point from mergerfs pool, unmount clean-up
  if mount_point
    mergerfs_modify_pool(:remove, '/storage', mount_point)
    run_command("/usr/bin/umount -l #{mount_point}")
    FileUtils.rm_rf(mount_point)
    logger(:info, "Unmounted #{mount_point}")
  end
end

exit(0)
