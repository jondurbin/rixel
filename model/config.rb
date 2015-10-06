class Rixel::Config
  LABEL_POSITION_VALIDATOR = Regexp.new('\A((north|south)(east|west)?|(east|west|center))\Z', true)
  COLOR_VALIDATOR = Regexp.new('\A([a-z0-9][a-z0-9\-]+[a-z0-9]|#[0-9a-f]{3,6})\Z', true)
  LABEL_BORDER_SIZE_VALUES = (1..5).collect

  # Wrap our config in the class method.
  class << self
    def config
      $rixel_config ||= Rixel::Config.new('config/rixel.yml')
    end
    def url
      config.url
    end
    def image_endpoint
      config.image_endpoint
    end
    def id_length
      config.id_length
    end
    def s3?
      config.s3
    end
    def path
      config.path
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
    def url_builder
      config.url_builder
    end
    def label_defaults
      config.label_defaults
    end
    def available_fonts
      config.available_fonts
    end
    def max_width
      config.max_width
    end
    def max_height
      config.max_height
    end
    def convert_path
      config.convert_path
    end
    def identify_path
      config.identify_path
    end
    def imgmin_path
      config.imgmin_path
    end
  end

  attr_reader :url              # URL format.
  attr_reader :image_endpoint   # Full URL endpoint with ID regex.
  attr_reader :id_length        # Number of characters to use for the ID length.
  attr_reader :s3               # S3 enabled?
  attr_reader :path             # Folder for storing images locally.
  attr_reader :s3_bucket_name   # Name of the bucket we'll be using.
  attr_reader :s3_path          # Path structure for the S3 bucket.
  attr_reader :cache_max_size   # Maximum size of cached files.
  attr_reader :cache_max_files  # Maximum number of cached files.
  attr_reader :url_builder      # Lambda function we'll use to generate image urls.
  attr_reader :label_defaults   # Default label values.
  attr_reader :available_fonts  # Array of available fonts.
  attr_reader :max_width        # Maximum width of an image.
  attr_reader :max_height       # Maximum height of an image.
  attr_reader :convert_path     # Path to the convert binary.
  attr_reader :identify_path    # Path to the identify binary.
  attr_reader :imgmin_path      # Path to imgmin.

  # Create a new Rixel configuration.
  def initialize(path)
    @rixel_config = YAML.load_file(path).symbolize_keys
    env  # Will raise an error unless the current env is defined.
    configure_binary_paths
    configure_id_length
    configure_url_format
    configure_image_endpoint
    configure_storage
    configure_max_size
    configure_available_fonts
    configure_label_settings
    #configure_face_samples
  end

  # Make sure our binaries actually work.
  def configure_binary_paths
    @convert_path = ((config[:imagemagick] || {})[:convert] || 'convert')
    @identify_path = ((config[:imagemagick] || {})[:identify] || 'identify')
    {'convert' => @convert_path, 'identify' => @identify_path}.each do |name, path|
      if name != path and not File.exists?(path)
        raise "Rixel::Config error - unable to find binary (#{name}) at: #{path}"
      end
      result = `#{Shellwords.escape(path)} -version`
      unless result =~ /\AVersion: ImageMagick/
        raise "Rixel::Config error - Unable to find valid ImageMagick #{name} binary#{path == name ? '' : " at #{path}"}"
      end
    end
    @imgmin_path = config[:imgmin_path]
    unless @imgmin_path.nil?
      result = system("#{Shellwords.escape(@imgmin_path)}")
      if result.nil?
        raise "Rixel::Config error - Unable to execute imgmin with path: #{@imgmin_path}"
      end
    end
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

  # Configure the ID pattern.
  def configure_image_endpoint
    pattern = config[:image_endpoint]
    pattern ||= '([^\\/]+)'
    @image_endpoint = Regexp.new(pattern)
puts "Image endpoint: #{@image_endpoint}"
  rescue => e
    raise "Rixel::Config error - Invalid image endpoint (pattern): #{e}"
  end 

  # Configure maximum size of an image.
  def configure_max_size
    if config[:max_size].nil?
      @max_width = 10000000000000000
      @max_width = 10000000000000000
      return
     end
    unless config[:max_size][:width].nil?
      @max_width = config[:max_size][:width].to_i
    end
    unless config[:max_size][:height].nil?
      @max_height = config[:max_size][:height].to_i
    end
  end

  # Configure available fonts.
  def configure_available_fonts
    @available_fonts = []
    ((config[:labels] || {})[:available_fonts] || []).each do |font|
      @available_fonts.push(font) if font.is_a?(String)
    end
  end

  # Configure label settings.
  def configure_label_settings
    @label_defaults = {}
    ((config[:labels] || {})[:default] || {}).each do |key, value|
      case key
      when :size
        unless "#{value}" =~ /\A\d+\Z/ and value.to_i >= 10 and value.to_i <= 100
          raise "Rixel::Config error - Invalid label size, must be between 10 and 100"
        end
        @label_defaults[:size] = value.to_s.to_i
      when :border_color
        unless "#{value}" =~ COLOR_VALIDATOR
          raise "Rixel::Config error - Invalid label border color, must be a known name, e.g. black, or a 3/6 character hex string"
        end
        @label_defaults[:border_color] = value.to_s
      when :border_size
        unless "#{value}" =~ /\A\d\Z/ and LABEL_BORDER_SIZE_VALUES.include?("#{value}".to_i)
          raise "Rixel::Config error - Invalid border size, must be an integer between #{BORDER_SIZE_VALUES.first} and #{BORDER_SIZE_VALUES.last}"
        end
        @label_defaults[:border_size] = value.to_s.to_i
      when :color
        unless "#{value}" =~ COLOR_VALIDATOR
          raise "Rixel::Config error - Invalid label color, must be a known name, e.g. black, or a 3/6 character hex string"
        end
        @label_defaults[:border_color] = value.to_s
      when :font
        unless @available_fonts.include?(value.to_s)
          raise "Rixel::Config error - Default font is not listed in the available fonts"
        end
        @label_defaults[:font] = value.to_s
      else
        puts "Rixel::Config - skipping unknown label default key: #{key} => #{value.to_s}"
      end
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
      @cache_max_files = nil
    else
      if "#{cache[:max_files]}".downcase =~ /\A\d+\Z/
        @cache_max_files = cache[:max_files].to_i
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
