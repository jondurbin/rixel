class Rixel::Image::File < File
  class << self
    def open(image)
      if image.is_a?(String)
        super(image)
      else
        if Rixel::Config.local_storage?
          super(image.image.file.path)
        else
          Rixel::Image::File::Cache.get(image)
        end
      end
    end
  end
end
