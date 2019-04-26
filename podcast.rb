require 'dotenv/load'
require "google_drive"
require 'aws-sdk'
require 'find'
require 'fileutils'
require 'rss'
require 'openssl'

require_relative './methods'

# Defaults
$publish=false
$rebuild=false

# Initialize build folders
dump_folder = 'calls' # where to download to from dropbox
staging_folder = 'staging' # where to assembly podcast
FileUtils.rm_rf(staging_folder)

# Get arguments
# e.g. -- episode=E4
# e.g. -- publish=true
# e.g. -- rebuild=true
args = Hash[ ARGV.join(' ').scan(/--?([^=\s]+)(?:=(\S+))?/) ]

if args['publish']=="true"
  $publish=true
end

if args['rebuild']=="true"
  $rebuild=true
end

# Initialize Google Drive Session and S3 Bucket
session = GoogleDrive::Session.from_service_account_key(StringIO.new(Base64.decode64(ENV['GOOGLE_DRIVE_AUTH_BASE64'])))
bucket = (Aws::S3::Resource.new).bucket(ENV['AWS_S3_BUCKET'])

# Use episode argument for episode or use the next episode
episode = args['episode'] || "E#{(bucket.objects.find_all { |object| object.key.include?('episodes/') }.count+1).to_s}"

# Create build folders
FileUtils::mkdir_p(staging_folder) # create dir if doesn't exist
FileUtils::mkdir_p(dump_folder) # create dir if doesn't exist

# Download files
download_files(session, dump_folder, episode)
$count = Dir[File.join(dump_folder, '**', '*')].count { |file| File.file?(file) }

# Assemble episode
combine_mp3s_transfer(staging_folder, dump_folder, bucket, episode)

# Rebuild podcast feed
rebuild_feed(bucket, session)

if $publish==true
  # Clean up
  FileUtils.rm_rf(staging_folder)
end