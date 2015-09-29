class Rixel::Image
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paperclip

  # Dimensions.
  field :w,  type: Integer
  field :h, type: Integer
  field :parent_id, type: String
  field :crop_x, type: Integer, default: 0
  field :crop_y, type: Integer, default: 0

  # Make sure we have a width and height.
  validates_presence_of :w
  validates_presence_of :h

  # Options.
  field :round, type: Boolean, default: false

  # Face recognition.
  embeds_many :faces, class_name: 'Rixel::Image::Face'

  # S3 callbacks.
  after_create :send_to_s3
  after_destroy :remove_from_s3

  # Make sure there's room for images when loading.
  before_create :make_room

  # Attached image.
  has_mongoid_attached_file(:image, {
    path: "#{Rixel::Config.path}/:id",
    url: Rixel::Config.url,
    styles: lambda do |a|
      if a.instance.round
        {
          original: {
            convert_options: a.instance.round_style,
            format: :png
          }
        }
      elsif a.instance.crop_x > 0 or a.instance.crop_y > 0
        {
          original: {
            convert_options: a.instance.crop_style
          }
        }
      else
        {original: "#{a.instance.w}x#{a.instance.h}#"}
      end
    end
  })
  validates_attachment :image, content_type: { content_type: /\Aimage\/.+\Z/ }


  # Get the URL for an image.
  def url
    Rixel::Config.url_builder.call(self.id)
  end

  # Round convert options.
  def round_style
    "\\( -size #{w}x#{h} xc:none -fill white -draw 'circle #{(w / 2).to_i},#{(h / 2).to_i} #{(w/ 2).to_i},0' \\) -compose copy_opacity -composite"
  end

  # Crop.
  def crop_style
    "-crop #{w}x#{h}+#{crop_x}+#{crop_y}"
  end

  # Store the image in S3.
  def send_to_s3
    return unless Rixel::Config.s3?
    return unless parent_id.nil?
    Rixel::S3Interface.put(self, image.queued_for_write[:original]) #.read)
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
    @original ||= Rixel::Image.where(parent_id: parent_id).first
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
    return width.to_i / (w / h)
  end

  # Calculate the width given a new height.
  def width_for_height(height)
    if height.to_i > h
      raise 'Invalid size - requested height is greater than original height'
    end
    return height.to_i * (w / h)
  end

  # Get the args to use for an image.
  def variant_args(options)
    if options[:h].nil? and not options[:w].nil?
      options[:h] = height_for_width(options[:w])
    elsif options[:w].nil? and not options[:h].nil?
      options[:w] = width_for_height(options[:h])
    end
    options[:w] = (options[:w] || w).to_i
    options[:h] = (options[:h] || h).to_i
    options[:crop_x] = (options[:crop_x] || 0).to_i
    options[:crop_y] = (options[:crop_y] || 0).to_i
    unless options[:crop_x].nil?
      if options[:crop_x] < 0 or options[:crop_x] > options[:w]
        raise "Invalid crop_x value"
      end
    end
    unless options[:crop_y].nil?
      if options[:crop_y] < 0 or options[:crop_y] > options[:h]
        raise "Invalid crop_y value"
      end
    end
    options
  end

  # Find a variant.
  def variant(options)
    # When no parameters are passed, it's the original.
    if options.empty?
      return self
    end

    # Check if all the options match the parent.
    mismatch = false
    options.each do |k, v|
      mismatch = true and break if self[k] != v
    end
    unless mismatch
      return self
    end

    # Find the variant (if any).
    Rixel::Image.where({parent_id: id}.merge(options)).first
  end

  # Get or create a new version of the image.
  def get_or_create_variant(options)
    options = variant_args(options)

    # Does the variant exist?
    existing = variant(options)
    unless existing.nil?
      return existing
    end

    # Same size, but other parameters are different.
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

  # Class methods.
  class << self
    # Create a new image from a file path.
    def create_from_file(path)
      geometry = Paperclip::Geometry.from_file(path) rescue nil
      raise 'Invalid image' if geometry.nil?

      # Try to save the image.
      image_args = {
        w: geometry.width,
        h: geometry.height,
        image: ::File.open(path)
      }
      image = Rixel::Image.new(image_args)
      begin
        image.save!
      rescue => e
        puts "Error saving image: #{e}, cleaning up..."
        rv = image.destroy rescue nil
      end
      image.save!
      image
    end

    # Load an image (either directly or from s3).
    def load(id)
      image = Rixel::Image.where(_id: id).first
      unless image.nil?
        if File.exists?(image.image.path)
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
end
