class Rixel::S3Interface
  class << self
    def bucket
      @bucket ||= AWS::S3.new.buckets[Rixel::Config.s3_bucket_name]
    end

    def path_for(id)
      Rixel::Config.s3_path.gsub(/^\//, '').gsub(':id', id)
    end

    def download(id, output_path)
      log(id, "Download")
      File.open(output_path, 'wb') do |output|
        bucket.objects[path_for(id)].read do |chunk|
          output.write(chunk)
        end
      end
    end

    def put(image, file)
      log(image.id, "Upload")
      bucket.objects.create(path_for(image.id), file)
    end

    def delete(id)
      log(id, "Delete")
      bucket.objects[path_for(id)].delete
    end

    def exists?(id)
      log(id, "Exists")
      bucket.objects[path_for(id)].exists?
    end
   private
    def log(id, action)
      puts "#{action} #{id} (S3::#{Rixel::Config.s3_bucket_name}::/#{path_for(id)})"
    end
  end
end
