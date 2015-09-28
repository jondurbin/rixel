class Rixel::Image::File::Cache
  MAX_FILES = nil
  MAX_SIZE = nil
  MAX_AGE = nil

  $lock = Mutex.new

  class << self
    # List the files in the cache directory.
    def list
      return @files unless @files.nil?
      @files = {}
      Dir.glob(File.join(Rixel::Config.cache_dir, '*')).each.collect do |path|
        mtime = File.stat(path).mtime
        @files[path] = {last_access: File.stat(path).mtime, size: File.size(path)}
      end
      @files
    end

    # Get the size of all files.
    def total
      return @total unless @total.nil?
      @total = 0
      list.each do |path, info|
        @total += info[:size]
      end
      @total
    end

    # Return the path to a cached file.
    def get(image)
      cleanup
      target = if image.is_a?(Rixel::Image)
        path = File.join(Rixel::Config.cache_dir, image.id)
        return download(image, path) if list[path].nil? or not File.exists?(path)
        Rixel::Image::File.open(path)
      else
        Rixel::Image::File.open(target)
      end
    end

    # Cleanup by max size.
    def trim_to_max_size
      unless MAX_SIZE.nil?
        if total > 0 and total > MAX_SIZE and MAX_SIZE > 0
          list.sort_by {|path, info| info[:last_access]}.reverse.each do |path, info|
            delete(path)
            break if total < MAX_SIZE
          end
        end
      end
    end

    # Cleanup by file count.
    def trim_to_max_files
      if not MAX_FILES.nil? and list.count > MAX_FILES
        list.sort_by {|path, info| info[:last_access]}.reverse.each do |path, info|
          delete(path)
          break if list.count < MAX_FILES
        end
      end
    end

    # Cleanup by age.
    def remove_expired
      unless MAX_AGE.nil? or MAX_AGE < 0
        list.each do |path, info|
          if info[:mtime] + MAX_AGE < Time.now
            delete(path)
          end
        end
      end
    end

    # Cleanup.
    def cleanup
      $lock.synchronize do
        trim_to_max_size
        trim_to_max_files
        remove_expired
      end
    end

    # Download an image.
    private
    def download(image, path)
      $lock.synchronize do
        s3_path = Paperclip::Attachment.default_options[:path].gsub(/^\//, '').gsub(':id', image.id)
        region = Paperclip::Attachment.default_options[:region]
        creds = Paperclip::Attachment.default_options[:s3_credentials]
        AWS.config(access_key_id: creds[:access_key_id], secret_access_key: creds[:secret_access_key], region: region)
        s3 = AWS::S3.new
        bucket_name = Paperclip::Attachment.default_options[:bucket]
puts "Trying to get #{s3_path} from #{region}"
        File.open(path, 'wb') do |output|
          output.write(s3.buckets[bucket_name].objects[s3_path].read)
        end
        @files[path] = {last_access: Time.now, size: File.size(path)}
        Rixel::Image::File.open(path)
      end
    end

    # Delete one file.
    def delete(path)
      info = list[path]
      return if info.nil?
      File.unlink(path)
      @total -= inf[:size]
      @files.delete(path)
    end
  end
end
