# https://gist.github.com/wteuber/5318013#file-encrypt_decrypt-rb
class String
  def encrypt(key)
    cipher = OpenSSL::Cipher.new('DES-EDE3-CBC').encrypt
    cipher.key =(Digest::SHA1.hexdigest key)[0, cipher.key_len]
    s = cipher.update(self) + cipher.final

    s.unpack('H*')[0].upcase
  end

  def decrypt(key)
    cipher = OpenSSL::Cipher.new('DES-EDE3-CBC').decrypt
    cipher.key = (Digest::SHA1.hexdigest key)[0, cipher.key_len]
    s = [self].pack("H*").unpack("C*").pack("c*")

    cipher.update(s) + cipher.final
  end
end

# Download every file for the given episode to specified local dump folder
def download_files(session, dump_folder, episode)
  recordings_folder = session.collection_by_url(ENV['GOOGLE_DRIVE_FOLDER_URL'])
  episode_folder = recordings_folder.subcollections(q: ["name contains ?", episode])[0]
  
  if episode_folder == nil
    puts "No calls for this episode."
  else
    episode_folder.files(q: ["mimeType = ?", "audio/mpeg"]) do |file|
      puts "Downloading #{file.title} ..."
      file.download_to_file("#{dump_folder}/#{file.title}")
    end
    
    # Write episode name to file
    puts "Recording episode name as #{episode_folder.title} ..."
    File.write("#{dump_folder}/episode_name.txt", episode_folder.title)
  end
end

def get_file_as_string(filename)
  data = ''
  f = File.open(filename, "r") 
  f.each_line do |line|
    data += line
  end
  return data
end

# Combine calls into one file and transfer to s3
def combine_mp3s_transfer(staging_folder, dump_folder, bucket, episode)
  
  if $count > 0
    temp_file = "temp.mp3"
    Dir.chdir(dump_folder) do
      Dir['*.mp3'].sort.each do |fn|
        `cat "#{fn}" >> #{temp_file}`
        puts "#{fn} >> #{temp_file}"
      end

      file_mtime = File.mtime(temp_file).to_s.gsub(' ','%')
      file_size = File.size(temp_file)
      episode_name = get_file_as_string('episode_name.txt').gsub(" ","-")
      file_name = "#{episode_name}_#{file_mtime}_#{file_size}"
      final_mp3 = "../#{staging_folder}/#{file_name}.mp3"
      File.rename(temp_file, final_mp3)

      if $publish==true
        # Deploy to S3
        puts "Finished deploying mp3 to AWS" 
        bucket.object("episodes/#{file_name.encrypt(ENV['ENCRYPT_SECRET'])}.mp3").upload_file(final_mp3)
      end
    end
  end
  # Clean up dump folder
  FileUtils.rm_rf(dump_folder)
end

def rebuild_feed(bucket, session)
  eps = Array.new
  bucket.objects.find_all { |object| object.key.include?('episodes/') }.each do |obj|
    if obj.key != "episodes/"
      eps.unshift(obj.key)
    end
  end

  base = ENV['PODCAST_BASEURL']
  rss = RSS::Maker.make("2.0") do |maker|
    maker.channel.title = ENV['PODCAST_TITLE']
    maker.channel.description = ENV['PODCAST_DESCRIPTION']
    maker.channel.link = base 
    maker.channel.language = 'en-us'
    maker.channel.about = base
    maker.items.do_sort = true # sort items by date
    maker.channel.updated = Time.now.to_s
    maker.channel.author = ENV['PODCAST_AUTHOR']
    maker.image.url = "#{base}avatar.png"
    maker.image.title = ENV['PODCAST_TITLE']

    i = 0
    for ep in eps
      i+=1
      if i <= ENV['MAX_EPISODES'].to_i
        item = maker.items.new_item
        ep_decoded = (ep.gsub('episodes/', '').gsub('.mp3', '')).decrypt(ENV['ENCRYPT_SECRET'])
        ep_details = ep_decoded.split('_')
        item.title = ep_details[0].gsub("-", " ")
        item.link = base + ep
        item.date = ep_details[1].gsub('%', ' ')      
        item.description = ''
        item.enclosure.url = base + ep
        item.enclosure.length = ep_details[2]
        item.enclosure.type = 'audio/mpeg'
      else
        if $publish==true
          bucket.object(ep).delete
        end
      end
    end
  end

  File.open("./staging/#{ENV['PODCAST_FILENAME']}.rss", 'w') { |file| file.write(rss) }
  if $rebuild==true || ($publish==true && $count > 0)
    bucket.object("#{ENV['PODCAST_FILENAME']}.rss").upload_file("./staging/#{ENV['PODCAST_FILENAME']}.rss")

    Dir.foreach('./public') do |item|
      next if item == '.' or item == '..'
      bucket.object(item).upload_file("./public/#{item}")
    end

    puts "Updated podcast feed."
  end
end

class String
  def rchomp(sep = $/)
    self.start_with?(sep) ? self[sep.size..-1] : self
  end
end
