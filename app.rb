require 'cuba'
require 'mongoid'
require 'mongoid_paperclip'
require 'aws-sdk'
require 'rack'
require 'getoptlong'
require 'thread'
require 'send_file'
require 'open-uri'
#require 'opencv'

# Rixel stuff.
require_relative 'model/rixel'
require_relative 'model/rixel/config'
require_relative 'model/rixel/s3_interface'
require_relative 'model/rixel/image'
require_relative 'model/rixel/image/file'
require_relative 'model/rixel/image/face'
require_relative 'model/rixel/image/file/cache'

# Mongoid configuration.
Mongoid.load!('config/mongoid.yml')

# Rixel configuration.
Rixel::Config.parse('config/rixel.yml')
image_endpoint = Rixel::Config.url.gsub(/^\//, '')

# Cuba configuration.
Cuba.plugin(SendFile)

# Server!
RixelServer = Cuba.define do
  # Get options from request.
  def options
    return @options unless @options.nil?
    @options = {}
    ['w', 'h', 'crop_x', 'crop_y'].each do |key|
      @options[key.to_sym] = req[key] if "#{req[key]}" =~ /\A\d+\Z/
    end
    @options[:round] = true if "#{req['round']}".downcase == 'true'
    @options
  end

  # Get an image.
  on get do
    on image_endpoint do |id|
      parent = Rixel::Image.load(id)
      on parent.nil? do
        res.status = 404
        halt(res.finish)
      end
      image = parent.variant(options)
      if image.nil?
        image = parent.create_variant(options)
      end
      send_file(Rixel::Image::File.open(image))
    end
    res.status = 404
  end

  # Add an image.
  on post do
    on 'image' do
      on param('file') do |image|
        on image[:tempfile].is_a?(Tempfile) do
          image = Rixel::Image.create(image[:tempfile].path) rescue nil
          on image.nil? do
            res.status = 422
            res.write 'Invalid image'
            halt(res.finish)
          end
          res.write image.image.url
        end
      end
    end
  end

  # Delete an image.
  on delete do
    on 'delete/:id' do |id|
      Rixel::Image.where({'$or' => [{_id: id}, {parent_id: id}]}).each {|image| image.destroy}
      res.write 'ok'
    end
  end
end
