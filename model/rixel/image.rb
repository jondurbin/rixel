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
  before_create :generate_id

  # Attached image.
  has_mongoid_attached_file(:image, {
    url: Rixel::Config.url,
    styles: lambda do |a|
      return {} if a.instance.round
      {original: "#{a.instance.w}x#{a.instance.h}#"}
    end,
    convert_options: { original: lambda {|image| image.convert_options} }
  })
  validates_attachment :image, content_type: { content_type: /\Aimage\/.+\Z/ }

  # Round convert options.
  def convert_options
    return '' unless round
    "\\( -size #{width}x#{height} xc:none -fill white -draw 'circle #{(width / 2).to_i},#{(height / 2).to_i} #{(width / 2).to_i},0' \\) -compose copy_opacity -composite"
  end

  # Generate a unique, short(er) ID.
  def generate_id
    while self._id = SecureRandom.urlsafe_base64(ID_LENGTH)
      break unless Rixel::Image.where(_id: self._id).exists?
    end
    self._id
  end

  # Find faces.
  def find_faces(file)
    self.faces = Rixel::Image::Face.detect(file)
  end

  # Parent image.
  def original
    @original ||= Rixel::Image.where(parent_id: parent_id).first
  end

  # File.
  def file
    Rixel::Image::File.open(self)
  end

  # Find a variant.
  def variant(options)
    return self if options.empty?
    Rixel::Image.where({parent_id: id}.merge(options)).first
  end

  # Convert the image to a new variant.
  def convert(options)
    existing = Rixel::Image.where({parent_id: id}.merge(options)).first
    return existing unless existing.nil?
    options = options.merge(parent_id: id, image: self.file)
    options[:w] ||= w
    options[:h] ||= h
    image = Rixel::Image.new(options)
    image.save!
    image
  end
end
