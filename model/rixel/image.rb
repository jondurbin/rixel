class Rixel::Image
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paperclip

  # Image ID length.
  ID_LENGTH = 6

  # Dimensions.
  field :w,  type: Integer
  field :h, type: Integer
  field :parent_id, type: String
  field :crop_x, type: Integer, default: nil
  field :crop_y, type: Integer, default: nil
  validates_presence_of :w
  validates_presence_of :h

  # Options.
  field :round, type: Boolean, default: false

  # Face recognition.
  embeds_many :faces, class_name: 'Rixel::Image::Face'

  # Generate a shorter image ID.
  field :skip_id_generation, type: Boolean, default: false
  before_create :generate_id

  # Attached image.
  has_mongoid_attached_file(:image, {
    url: Rixel::Config.url,
    styles: lambda do |a|
      if a.instance.round
        return {
          original: {
            convert_options: a.instance.round_style,
            format: :png
          }
        }
      end
      {original: "#{a.instance.w}x#{a.instance.h}#"}
    end
  })
  validates_attachment :image, content_type: { content_type: /\Aimage\/.+\Z/ }

  # Round convert options.
  def round_style
    "\\( -size #{w}x#{h} xc:none -fill white -draw 'circle #{(w / 2).to_i},#{(h / 2).to_i} #{(w/ 2).to_i},0' \\) -compose copy_opacity -composite"
  end

  # Generate a unique, short(er) ID.
  def generate_id
    return if skip_id_generation
    while self._id = SecureRandom.urlsafe_base64(ID_LENGTH)
      break unless Rixel::Image.where(_id: self._id).exists?
    end
    self._id
  end

  # Find faces.
  def find_faces(input_file=get_file)
    self.faces = Rixel::Image::Face.detect(input_file)
  end

  # Parent image.
  def original
    @original ||= Rixel::Image.where(parent_id: parent_id).first
  end

  # File.
  def get_file
    Rixel::Image::File.open(self)
  end

  # Filename (for response header).
  def filename
    "#{id.to_s}.#{image_file_name.split('.').last}"
  end

  # Find a variant.
  def variant(options)
    return self if options.empty?
    mismatch = false
    options.each do |k, v|
      mismatch = true and break if self[k] != v
    end
    return self unless mismatch
    Rixel::Image.where({parent_id: id}.merge(options)).first
  end

  # Convert the image to a new variant.
  def create_variant(options)
    v = variant(options)
    return v unless v.nil?

    # Default is to copy the height and width.
    options[:w] ||= w
    options[:h] ||= h

    # Same size?
    if options[:w] == w and options[:h] == h
      image = Rixel::Image.new(options.merge(parent_id: id, image: get_file))
      image.save!
      return image
    end

    # New size.
    base_options = {parent_id: id, w: options[:w], h: options[:h]}
    starting_image = Rixel::Image.where(base_options).first
    if starting_image.nil?
      starting_image = Rixel::Image.new(base_options.merge(image: get_file))
      starting_image.save!
    end

    # Apply any further transforms.
    mismatch = false
    options.each do |k, v|
      mismatch = true and break if starting_image[k] != v
    end
    return starting_image unless mismatch

    final_image = Rixel::Image.new(options.merge(parent_id: id, image: starting_image.get_file))
    final_image.save!
    final_image
  end

  # Create a new image from a file path.
  def self.create(path, id=nil)
    geometry = Paperclip::Geometry.from_file(path) rescue nil
    raise 'Invalid image' if geometry.nil?

    # Try to save the image.
    image_args = {
      w: geometry.width,
      h: geometry.height,
      image: ::File.open(path)
    }
    image_args[:_id] = id unless id.nil?
    image_args[:skip_id_generation] = true unless id.nil?
    image = Rixel::Image.new(image_args)
    #image.find_faces(image[:tempfile])
    image.save!
    image
  end

  class << self
    # Load an image (either directly or from s3).
    def load(id)
      image = Rixel::Image.where(_id: id).first
      return image unless image.nil?
      return nil if Rixel::Config.local_storage?
      return nil unless Rixel::S3Interface.exists?(id)
      temp_path = Tempfile.new('rixel')
      Rixel::S3Interface.download(id, temp_path)
      image = Rixel::Image.create(temp_path, id)
      File.unlink(temp_path)
      image
    end
  end
end
