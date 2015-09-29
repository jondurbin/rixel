class Rixel::Config

  # Wrap our config in the class method.
  class << self
    def config
      $config ||= Rixel::Config.new('config/rixel.yml')
    end
    def id_length
      config.id_length
    end
    def path
      config.path
    end
    def s3?
      config.s3
    end
    def s3_bucket_name
      config.s3_bucket_name
    end
    def s3_path
      config.s3_path
    end
    def cache_max_size
      config.cache_max_size
    end
    def cache_max_files
      config.cache_max_files
    end
    def url
      config.url
    end
    def url_builder
      config.url_builder
    end
  end

  attr_reader :url              # URL format.
  attr_reader :id_length        # Number of characters to use for the ID length.
  attr_reader :s3               # S3 enabled?
  attr_reader :path             # Folder for storing images locally.
  attr_reader :s3_bucket_name   # Name of the bucket we'll be using.
  attr_reader :s3_path          # Path structure for the S3 bucket.
  attr_reader :cache_max_size   # Maximum size of cached files.
  attr_reader :cache_max_files  # Maximum number of cached files.
  attr_reader :url_builder      # Lambda function we'll use to generate image urls.

  # Create a new Rixel configuration.
  def initialize(path)
    @rixel_config = symbolize_keys(YAML.load_file(path))
    env  # Will raise an error unless the current env is defined.
    configure_id_length
    configure_url_format
    configure_storage
    #configure_face_samples
  end

  # Configure ID length.
  def configure_id_length
    @id_length = config[:id_length]
    @id_length ||= 8
    unless "#{@id_length}" =~ /\A\d+\Z/
      raise "Rixel::Config error - Invalid ID length: #{config[:id_lenght]}"
    end
  end

  # Configure the URL format we'll be using.
  def configure_url_format
    @url = config[:url]
    if "#{@url}" =~ /\A(\/[a-z0-9\-_]+)*\/:id(\/[a-z0-9\-_\/]*)?\Z/
      @url_builder = lambda {|id| @url.gsub(/:id/, id)}
    else
      raise "Rixel::Config error - Invalid URL format: #{url}"
    end
  end

  # Configure the storage.
  def configure_storage
    storage = config[:storage]
    if storage.nil?
      raise 'Rixel::Config error - storage not specified!'
    end
    configure_storage_directory
    configure_s3_settings
    configure_cache_settings
  end

  # Configure the storage directory.
  def configure_storage_directory
    @path = config[:storage][:path]
    if @path.nil?
      raise "Rixel::Config error - no storage path specified"
    end
    unless File.directory?(@path)
      raise "Rixel::Config error - #{@path} is not a directory"
    end
    begin
      test_path = File.join(@path, SecureRandom.uuid)
      File.open(test_path, 'w') do |f|
        f.puts "rixel write test"
      end
      File.unlink(test_path)
    rescue => e
      raise "Rixel::Config error - Unable to write to #{@path}: #{e}"
    end
    Paperclip::Attachment.default_options[:storage] = :filesystem
    Paperclip::Attachment.default_options[:path] = "#{@path}/:id"
    true
  end

  # Configure the cache settings.
  def configure_cache_settings
    return unless s3?
    cache = config[:storage][:s3][:cache]
    if cache.nil?
      @cache_max_size = nil
      @cache_max_files = nil
      return
    end
    if cache[:max_size].nil?
      @cache_max_size = nil
    else
      if "#{cache[:max_size]}".downcase =~ /\A(\d+)([mg])?\Z/
        @cache_max_size = $1.to_i * 1024 * 1024 * {'m' => 1, 'g' => 1025}[$2 || "m"]
      else
        raise "Rixel::Config error - invalid cache max_size value: #{cache[:max_size]}"
      end
    end
    if cache[:max_files].nil?
      @cache_max_size = nil
    else
      if "#{cache[:max_size]}".downcase =~ /\A\d+\Z/
        @cache_max_size = cache[:max_size].to_i
      else
        raise "Rixel::Config error - invalid cache max_files value: #{cache[:max_files]}"
      end
    end
  end

  # Configure S3.
  def configure_s3_settings
    s3 = config[:storage][:s3]
    if s3.nil?
      @s3 = false
      return
    end
    credentials = s3[:s3_credentials]
    unless credentials.is_a?(Hash)
      raise "Rixel::Config error - s3 specified without s3_credentials hash"
    end
    if credentials[:access_key_id].nil?
      raise "Rixel::Config error - access_key_id not specified"
    end
    if credentials[:secret_access_key].nil?
      raise "Rixel::Config error - secret_access_key not specified"
    end
    @s3_bucket_name = s3[:bucket_name]
    if @s3_bucket_name.nil?
      raise "Rixel::Config error - bucket name not specified"
    end
    @s3_path = s3[:path]
    if @s3_path.nil?
      raise "Rixel::Config error - s3_path not specified"
    end
    AWS.config(
      access_key_id: credentials[:access_key_id],
      secret_access_key: credentials[:secret_access_key]
    )
    @s3 = true
    true
  end

  # S3 enabled?
  def s3?
    @s3
  end

 private
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

  # Get the current environment.
  def env
    return @env if @env
    e = ENV['MONGOID_ENV'] || ENV['RACK_ENV']
    if e.nil? or @rixel_config[e.to_sym].nil?
      raise "No configuration specified for environment '#{e}'"
    end
    @env = e.to_sym
    @env
  end

  # Get the raw config.
  def config
    @rixel_config[env]
  end
end
