class Rixel::S3Interface
  class << self
    def bucket
      return @bucket unless @bucket.nil?
      region = Paperclip::Attachment.default_options[:region]
      creds = Paperclip::Attachment.default_options[:s3_credentials]
      AWS.config(access_key_id: creds[:access_key_id], secret_access_key: creds[:secret_access_key], region: region)
      s3 = AWS::S3.new
      bucket_name = Paperclip::Attachment.default_options[:bucket]
      @bucket = s3.buckets[bucket_name]
      @bucket
    end

    def path_for(id)
      Paperclip::Attachment.default_options[:path].gsub(/^\//, '').gsub(':id', id)
    end

    def download(id, output_path)
      File.open(output_path, 'wb') do |output|
        output.write(bucket.objects[path_for(id)].read)
      end
    end

    def exists?(id)
      bucket.objects[path_for(id)].exists?
    end
  end
end
