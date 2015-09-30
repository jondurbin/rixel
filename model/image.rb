class Rixel::Image
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paperclip
  include AutoCode

  auto_load true, :directories => ['model/image']

  # Dimensions.
  field :w,  type: Integer
  field :h, type: Integer
  field :parent_id, type: String
  field :crop_x, type: Integer, default: 0
  field :crop_y, type: Integer, default: 0
  field :x, type: Integer, default: 0
  field :y, type: Integer, default: 0
  field :label_args, type: Array, default: []
  field :signature, type: String

  # Options.
  field :round, type: Boolean, default: false

  # Face recognition.
  has_many :faces, class_name: 'Rixel::Image::Face', dependent: :destroy

  # Labels.
  has_many :labels, class_name: 'Rixel::Image::Face', dependent: :destroy

  # S3 callbacks.
  after_create :send_to_s3
  after_destroy :remove_from_s3

  # Make sure there's room for images when loading.
  before_create :make_room

  # Before saving, validate args and generate the signature.
  after_initialize :generate_signature

  # Attached image.
  has_mongoid_attached_file(:image, {
    path: "#{Rixel::Config.path}/:id",
    url: Rixel::Config.url,
    styles: lambda do |a|
      {
        original: {
          convert_options: a.instance.generate_convert_options,
          format: :png
        }
      }
    end
  })
  validates_attachment :image, content_type: { content_type: /\Aimage\/.+\Z/ }

  # Class methods.
  class << self
    # Create a new image from a file path.
    def create_from_file(path, id=nil, args={})
      geometry = Paperclip::Geometry.from_file(path) rescue nil
      raise 'Invalid image' if geometry.nil?

      # Try to save the image.
      image_args = {
        w: geometry.width,
        h: geometry.height,
        image: ::File.open(path)
      }.merge(args.symbolize_keys)
      image = Rixel::Image.new(image_args)
      image.id = id unless id.nil?
      begin
        image.save!
      rescue => e
        puts "Error saving image: #{e}, cleaning up..."
        rv = image.destroy rescue nil
      end
      image
    end

    # Load an image (either directly or from s3).
    def load(id)
      image = Rixel::Image.where(_id: id).first
      unless image.nil?
        if File.exists?(image.image.path)
          image.update_attributes!(updated_at: Time.now)
          return image
        else
          image.destroy
        end
      end

      # (Try) to download from s3.
      if Rixel::Config.s3? and Rixel::S3Interface.exists?(id)
        Rixel::S3Interface.download(id, File.join(Rixel::Config.path, id))
        image = Rixel::Image.create_from_file(temp_path, id)
        return image
      end
      nil
    end
  end

  # Hash of all the args.
  def to_hash
    {
      id: id.to_s,
      w: w,
      h: h,
      parent_id: parent_id,
      crop_x: crop_x,
      crop_y: crop_y,
      x: x,
      y: y,
      labels: labels.each.collect {|label| label.to_hash},
      faces: faces.each.collect {|face| face.to_hash}
    }
  end

  # Generate a signature.
  def generate_signature
    self.signature = Digest::MD5.hexdigest(Marshal.dump(to_hash.merge(id: nil)))
    self.signature
  end

  # Get the URL for an image.
  def url
    Rixel::Config.url_builder.call(self.id)
  end

  # Size style.
  def size_args
    "-resize '#{w}x#{h}^' -gravity center -extent #{w}x#{h}"
  end

  # Round convert options.
  def round_args
    return unless round
    diameter = [w, h].min
    radius = (diameter / 2).to_i
    " - | #{Shellwords.escape(Rixel::Config.convert_path)} -resize '#{diameter}x#{diameter}^' -gravity center -extent #{diameter}x#{diameter} -size #{diameter}x#{diameter} xc:transparent -fill - -draw 'circle #{radius},#{radius} #{radius},0' +repage"
  end

  # Crop.
  def crop_args
    return nil unless crop_x > 0 or crop_y > 0
    "-crop #{w}x#{h}-#{crop_x}-#{crop_y}"
  end

  # Offset.
  def offset_args
    return nil unless x > 0 or y > 0
    "-crop #{w}x#{h}+#{x}+#{y}"
  end

  # Labels.
  def img_label_args
    args = self.labels.each.collect do |label|
      [
        "-pointsize #{label.size}",
        "-gravity #{label.pos}",
        "-font #{label.font}",
        "-fill #{label.color}",
        "-stroke #{label.border_color}",
        "-strokewidth #{label.border_size}",
        "-annotate 0 '#{label.text}'"
      ].join(' ')
    end.join(' ')
    args = nil if args.empty?
    args
  end

  # Generate the style.
  def generate_convert_options
    validate_args
    [
      size_args,
      offset_args,
      crop_args,
      img_label_args,
      round_args
    ].delete_if {|arg| arg.nil?}.join(' ')
  end

  # Store the image in S3.
  def send_to_s3
    return unless Rixel::Config.s3?
    return unless parent_id.nil?
    Rixel::S3Interface.put(self, image.queued_for_write[:original])
  end

  # Delete the image from S3.
  def remove_from_s3
    return unless Rixel::Config.s3?
    return unless parent_id.nil?
    Rixel::S3Interface.delete(id)
  end

  # Get the total size.
  def get_total_size
    Rixel::Image.sum(:image_file_size)
  end

  # Make room for images.
  def make_room
    return unless Rixel::Config.s3?
    unless Rixel::Config.cache_max_files.nil?
      while Rixel::Image.count > Rixel::Config.cache_max_files
        Rixel::Image.all.sort(updated_at: 1).first.destroy
      end
    end
    unless Rixel::Config.cache_max_size.nil?
      while Rixel::Image.sum(:image_file_size) > Rixel::Config.cache_max_size
        Rixel::Image.all.sort(updated_at: 1).first.destroy
      end
    end
  end

  # Find faces.
  def find_faces(input_file=get_file)
    self.faces = Rixel::Image::Face.detect(input_file)
  end

  # Parent image.
  def original
    @original ||= if parent_id.nil?
      self
    else
      Rixel::Image.where(parent_id: parent_id).first
    end
    @original
  end

  # File.
  def get_file
    Rixel::Image::File.open(self)
  end

  # Calculate height given a new width.
  def height_for_width(width)
    if width.to_i > w
      raise 'Invalid size - requested width is greater than original'
    end
    width.to_i / (w / h)
  end

  # Calculate the width given a new height.
  def width_for_height(height)
    if height.to_i > h
      raise 'Invalid size - requested height is greater than original height'
    end
    height.to_i * (w / h)
  end

  # Find a variant.
  def find_variant(options)
    temp = Rixel::Image.new(options)
    temp.validate_args
    Rixel::Image.where(signaure: temp.generate_signature).first
  end

  # Get or create a new version of the image.
  def get_or_create_variant(options)
    variant = find_variant(options)
    if variant.nil?
      variant = Rixel::Image.new(options)
      variant.save!
    end
    variant
  end

  # Convert input args to validated args.
  def validate_args
    self.w = validated_width
    self.h = validated_height
    self.x = validated_x
    self.y = validated_y
    self.crop_x = validated_crop_x
    self.crop_y = validated_crop_y
    self.round = round.is_a?(Boolean) ? round : false
    self.labels = self.label_args.each.collect do |args|
      label = Rixel::Image::Label.new(args)
      puts label.to_hash
      label
    end.delete_if {|label| not label.is_valid}
  end

  private
  def validate_and_generate_signature
    validate_args
    generate_signature
  end

  def validated_width
    width = nil
    if w.nil? and not h.nil?
      if h.is_a?(Numeric) and h > 0 and h <= original.h
        width = height_for_width(h.to_i)
      end
    elsif w.is_a?(Numeric) or "#{w}" =~ /\A\d+(\.\d+)?\Z/
      width = "#{w}".to_i
    end
    width = original.w unless width.is_a?(Integer) and width <= 0
    width = [width, Rixel::Config.max_width].min
    width
  end

  def validated_height
    height = nil
    if h.nil? and not w.nil?
      if w.is_a?(Numeric) and w > 0 and w <= original.w
        height = height_for_width(w.to_i)
      end
    elsif h.is_a?(Numeric) or "#{h}" =~ /\A\d+(\.\d+)?\Z/
      height = "#{h}".to_i
    end
    height = original.h unless height.is_a?(Integer) and height <= 0
    height = [height, Rixel::Config.max_height].min
    height
  end

  def validated_x
    return 0 unless x.is_a?(Integer) and x > 0 and x < w
    x
  end

  def validated_y
    return 0 unless y.is_a?(Integer) and y > 0 and y < h
    y
  end

  def validated_crop_x
    return 0 unless crop_x.is_a?(Integer) and crop_x > 0 and crop_x < w - x
    crop_x
  end

  def validated_crop_y
    return 0 unless crop_y.is_a?(Integer) and crop_y > 0 and crop_y < h - y
    crop_y
  end
end
