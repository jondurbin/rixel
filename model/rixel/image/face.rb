class Rixel::Image::Face
  include Mongoid::Document
  #include OpenCV

  # Rectangle stuff.
  field :x, type: Integer
  field :y, type: Integer
  field :width, type: Integer
  field :height, type: Integer

  # Detect faces.
  def self.detect(path)
    @faces = []
    detector = CvHaarClassifierCascade::load(Config.face_sample_path)
    image = CvMat.load(path)
    detector.detect_objects(image).each.collect do |region|
      @faces.push(Face.new(
        x: region.top_left.y,
        y: region.top_left.y,
        width: region.bottom_right.x - region.top_left.y,
        height: region.bottom_right.y - region.top_left.y
      ))
    end
    @faces
  rescue => e
    puts "Error detecting faces: #{e}\n#{e.backtrace.join("\n")}"
    @faces
  end
end
