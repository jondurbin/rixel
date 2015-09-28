class Rixel::Config
  class << self
    def ensure_initialized
      return if @parsed
      Rixel::Config.parse('config/rixel.yml')
      @parsed = true
    end

    # Symbolize keys.
    def symbolize_keys(hash)
      symbolized = {}
      hash.each do |key, value|
        if value.is_a?(Hash)
          symbolized[key.to_sym] = symbolize_keys(value)
        elsif value.is_a?(Array)
          value.each do |item|
            if item.is_a?(Hash)
              item = symbolize_keys(item)
            end
          end
        else
          symbolized[key.to_sym] = value
        end
      end
      symbolized
    end

    # Parse a YAML configuration file.
    def parse(path)
      options = symbolize_keys(YAML.load_file(path))
      configure_storage(options)
      unless local_storage?
        configure_cache(options[:storage])
      end
      @url = options[:url]
    end

    # Configure the S3 cache options.
    def configure_cache(options)
      @cache_dir = options[:cache].nil? ? nil : options[:cache][:path]

      # Max age?
      if options[:cache][:max_age] and options[:cache][:max_age] =~ /\A(\d+)([smhd])?\Z/
        value = $1.to_i
        multiplier = $2.nil? ? 1 : {'s' => 1, 'm' => 60, 'h' => 60 * 60, 'd' => 60 * 24}[$2]
        @max_age = value * multiplier
      end

      # Max files?
      if options[:cache][:max_files] and "#{options[:cache][:max_files]}" =~ /\A(\d+)\Z/
        @max_files = options[:cache][:max_files].to_i
      end

      # Max size?
      if options[:cache][:max_size] and "#{options[:cache][:max_size]}".downcase =~ /\A(\d+)([kmg])\Z/
        value = $1.to_i
        multiplier = $2.nil? ? 1 : {'k' => 1024, 'm' => 1024 * 1024, 'g' => 1024 * 1024 * 1024}[$2]
        @max_size = value * multiplier
      end
    end

    # Configure the storage options.
    def configure_storage(options)
      storage = options[:storage]
      if not storage[:s3].nil?
        use_s3(storage[:s3])
      elsif not storage[:local].nil?
        use_local(storage[:local])
      else
        raise 'No storage backend specified!'
      end
    end

    # Configure the URL.
    def url
      ensure_initialized
      @url
    end

    # Get or set cache dir.
    def cache_dir
      @cache_dir
    end

    # Configure s3 as the storage.
    def use_s3(options)
      @s3 = true
      Paperclip::Attachment.default_options[:path] = options[:path]
      Paperclip::Attachment.default_options[:bucket] = options[:bucket]
      Paperclip::Attachment.default_options[:storage] = :s3
      Paperclip::Attachment.default_options[:s3_credentials] = {
        access_key_id: options[:access_key_id],
        secret_access_key: options[:secret_access_key]
      }
      Paperclip::Attachment.default_options[:s3_host_name] = options[:s3_host_name]
      Paperclip::Attachment.default_options[:s3_host_alias] = options[:s3_host_alias]
    end

    # Set max age.
    def max_age
      @max_age
    end

    # Max size.
    def max_size
      @max_size
    end

    # Max file count.
    def max_files
      @max_files
    end

    # Configure local storage.
    def use_local(options)
      @s3 = false
      Paperclip::Attachment.default_options[:storage] = :filesystem
      Paperclip::Attachment.default_options[:path] = options[:path]
    end

    # Locally stored?
    def local_storage?
     @s3 ? false : true
    end

    # Set the face recognition sample path.
    def face_sample_path
      @face_sample_path
    end
  end
end
