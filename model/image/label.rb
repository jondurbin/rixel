class Rixel::Image::Label
  include Mongoid::Document

  VALID_FIELDS = [:text, :font, :size, :pos, :color, :border_color, :border_size]

  # The label text.
  field :text, type: String

  # The font.
  field :font, type: String

  # Font size.
  field :size, type: Integer

  # Position, which in IM terms is 'gravity'
  field :pos, type: String

  # String color.
  field :color, type: String

  # Outline color
  field :border_color, type: String

  # Outline size.
  field :border_size, type: Integer

  # Valid?
  field :is_valid, type: Boolean, default: true

  # Belongs to an image.
  embedded_in :image

  # Before saving, validate and/or use defaults.
  after_initialize :get_validated_args

  # As a hash.
  def to_hash
    {
      text: text,
      font: font,
      size: size,
      pos: pos,
      color: color,
      border_color: border_color,
      border_size: border_size
    }
  end

  # Field validators.
  private
  def get_validated_args
    self.text = validated_text
    self.font = validated_font
    self.size = validated_size
    self.pos = validated_position
    self.color = validated_color
    self.border_color = validated_border_color
    self.border_size = validated_border_size
  end

  def validated_text
    t = self.text.encode('UTF-8', :undef => :replace, :invalid => :replace, :replace => '').gsub(/[\r\n]/) {|t| ' '} rescue nil
    if t.length > 100
      t = "#{t[0..100]}..."
    end
    if t.length == 0
      self.valid = false
      return ""
    end
    Shellwords.escape(t)
  end

  def validated_font
    if Rixel::Config.available_fonts.include?(font)
      font
    elsif Rixel::Config.label_defaults[:font].nil?
      self.valid = false
      return ""
    else
      Rixel::Config.label_defaults[:font]
    end
  end

  def validated_size
    if size.is_a?(Numeric) and size > 0 and size < 100
      size
    else
      Rixel::Config.label_defaults[:size] || 30
    end
  end

  def validated_position
    if "#{pos}" =~ Rixel::Config::LABEL_POSITION_VALIDATOR
      "#{pos}".downcase
    else
      Rixel::Config.label_defaults[:pos] || 'center'
    end
  end

  def validated_color
    if "#{color}" =~ Rixel::Config::COLOR_VALIDATOR
      "#{color}".downcase
    else
      Rixel::Config.label_defaults[:color] || 'white'
    end
  end

  def validated_border_color
    if "#{border_color}" =~ Rixel::Config::COLOR_VALIDATOR
       "#{border_color}".downcase
    else
      Rixel::Config.label_defaults[:border_color] || 'black'
    end
  end

  def validated_border_size
    if "#{border_size}" =~ /\A[0-9]+\Z/
      w = border_size.to_i
      if Rixel::Config::LABEL_BORDER_SIZE_VALUES.include?(w)
        return w
      end
    end
    Rixel::Config.label_defaults[:border_size] || 1
  end
end
