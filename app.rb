require 'cuba'
require 'mongoid'
require 'mongoid_paperclip'
require 'aws-sdk'
require 'rack'
require 'getoptlong'
require 'thread'
require 'send_file'
require 'open-uri'
require 'shellwords'
require 'autocode'
require 'digest'
#require 'opencv'

# Symbolize keys helper.
class Hash
  def symbolize_keys
    inject({}){|result, (key, value)|
      new_key = case key
      when String then key.to_sym
      else key
      end
      new_value = case value
      when Hash then value.symbolize_keys
      when Array then value.each.collect {|item| item.is_a?(Hash) ? item.symbolize_keys : item}
      else value
      end
      result[new_key] = new_value
      result
    }
  end
end

# Rixel stuff.
module Rixel
  include AutoCode
  auto_load true, :directories => [:model]
end

# Mongoid configuration.
Mongoid.load!('config/mongoid.yml')

# Rixel configuration.
image_endpoint = Rixel::Config.url.gsub(/^\//, '')

# Cuba configuration.
Cuba.plugin(SendFile)

# Server!
RixelServer = Cuba.define do
  # Get options from request.
  def options
    return @options unless @options.nil?
    @options = {}
    ['w', 'h', 'x', 'y', 'crop_x', 'crop_y'].each do |key|
      @options[key.to_sym] = req.params[key] if "#{req.params[key]}" =~ /\A\d+\Z/
    end
    @options[:round] = true if "#{req.params['round']}".downcase == 'true'
    if req.params['label'].is_a?(String)
      @options[:labels] = [{text: req.params['label']}]
    elsif req.params['label'].is_a?(Hash)
      @options[:labels] = [req.params['label'].symbolize_keys]
    elsif req.params['label'].is_a?(Array)
      @options[:labels] = req.params['label'].each.collect do |label|
        if label.is_a?(String)
          {text: label}
        elsif label.is_a?(Hash)
          label.symbolize_keys
        else
          nil
         end
      end.delete_if {|label| label.nil?}
    end
    @options[:labels].each do |args|
      args.delete_if {|key, value| not Rixel::Image::Label::VALID_FIELDS.include?(key.to_sym)}
    end
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
      image = parent.get_or_create_variant(options)
      res.headers["Content-Type"] = "image/png"
      res.headers["Content-Disposition"] = "inline"
      res.write(image.get_file.read)
    end
    res.status = 404
  end

  # Add an image.
  on post do
    on 'image' do
      on param('file') do |image|
        on image[:tempfile].is_a?(Tempfile) do
          image = Rixel::Image.create_from_file(image[:tempfile].path, req.params['id'], options)
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
