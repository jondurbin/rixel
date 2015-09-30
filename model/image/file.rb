class Rixel::Image::FileHelper
  class << self

    # Open a file by path or by Rixel::Image object.
    def open(image)
      # Regular filename?
      return File.open(image) if image.is_a?(String)

      # Stored locally?
      path = File.join(Rixel::Config.path, image.id)
      if File.exists?(path)
        return File.open(path)
      end

      # Download from S3.
      if Rixel::Config.s3?
        Rixel::S3Interface.download(image.id, path)
        return File.open(path)
      end
      nil
    end

  end
end
