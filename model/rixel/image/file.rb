class Rixel::Image::File < File
  class << self

    # Open a file by path or by Rixel::Image object.
    def open(image)
      # Regular filename?
      return super(image) if image.is_a?(String)

      # Stored locally?
      path = File.join(Rixel::Config.path, image.id)
      if File.exists?(path)
        return super(path)
      end

      # Download from S3.
      Rixel::S3Interface.download(image.id, path)
      super(path)
    end

  end
end
