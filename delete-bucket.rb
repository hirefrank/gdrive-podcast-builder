require 'dotenv/load'
require "google_drive"
require 'aws-sdk'
require 'find'
require 'fileutils'
require 'rss'

# resets the episodes bucket
bucket = (Aws::S3::Resource.new).bucket(ENV['AWS_S3_BUCKET'])
bucket.objects.find_all { |object| object.key.include?('episodes/') }.each do |obj|
  if obj.key != "episodes/"
    #eps.unshift(obj.key)
    bucket.object(obj.key).delete
  end
end
