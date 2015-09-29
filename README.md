# rixel
Rixel - ruby web-server for on-the-fly image resizing, shaping, cropping and face recognition.

# Rixel
Rixel is a ruby web-server which servers as an image proxy that can transform images on-the-fly based on URL parameters.  Rixel supports local disk storage as well as AWS S3.  When using S3, rixel uses LRU disk caching, with configurable values for maximum cache files, total cache size, or max age of the file.

## Installation

### Dependencies
1. ruby-2.2.2 (hint: rvm is awesome)
2. mongodb
3. Bundler (gem install bundler)

### Install
1. Clone or fork this project.
2. Update the mongoid configuration (config/mongoid.yml)
3. Update the rixel configuration (config/rixel.yml)
4. Install gems used by pixel with bundler: bundle
5. *To support face recognition (coming soon) and automatic face cropping, you must install opencv 2.4.11 (opencv 3.* doesn't play nicely with the ruby-opencv gem in my experience).

### Rixel config
```yaml
production:
  url: /images/:id
  storage:
    path: /path/to/local/rixel/storage
    s3:
      s3_credentials:
        access_key_id: AWS_ACCESS_KEY_ID
        secret_access_key: AWS_SECRET_ACCESS_KEY
      bucket_name: AWS_BUCKET_NAME
      path: /images/:id
      cache:
        max_files: 1000
        max_size: 1g
```
#### Description
1. url: The path used for serving images, e.g. /path/to/image/:id
2. storage: Storage configuration
3. storage.path: Path to local storage (serves as cache directory when using S3)
4. storage.s3: AWS S3 configuration
5. storage.s3.cache: Configure how many files and/or max size of the local cache directory.

## Running the server
bundle exec puma -e ENVIRONMENT -p PORT, for example:
bundle exec puma -e production -p 80

# Accessing the console
```bash
cd /path/to/rixel; MONGOID_ENV=production bundle exec irb -r ./app.rb
```

# Creating an image.
## Via console:
```ruby
Rixel::Image.create_from_file('/path/to/image.jpg', 'image.jpg')
```
## Via curl:
```bash
curl -XPOST -f "file=@filename.jpg" http://RIXEL_HOST/image
# This will spit out the *relative* to the image.
```
### To disable image uploads via post, edit app.rb, change the `on post` method to:
```ruby
on post do
  res.status = 403
end
```

# Examples:
## Resizing: GET /images/test.jpg?w=300&h=300
![/images/test.jpg?w=300&h=300](https://github.com/jondurbin/rixel/raw/master/examples/resize.jpg)
## Resize and circle overlay: GET /images/test.jpg?w=300&h=300&round=true
![/images/test.jpg?w=300&h=300&round=true](https://github.com/jondurbin/rixel/raw/master/examples/resize_round.png)
## Resize and offset: GET /images/test.jpg?w=300&h=300&x=50&y=50
![/images/test.jpg?w=300&h=300&x=50&y=50](https://github.com/jondurbin/rixel/raw/master/examples/resize_offset.jpg)
## Resize, offset and crop: GET /images/test.jpg?w=300&h=300&x=50&y=50&crop_x=50&crop_y=50
![/images/test.jpg?w=300&h=300&x=50&y=50&crop_x=50&crop_y=50](https://github.com/jondurbin/rixel/raw/master/examples/resize_offset_crop.jpg)
## Resize, offset, crop and circle overlay: GET /images/test.jpg?w=300&h=300&x=50&y=50&crop_x=50&crop_y=50&round=true
![/images/test.jpg?w=300&h=300&x=50&y=50&crop_x=50&crop_y=50&round=true](https://github.com/jondurbin/rixel/raw/master/examples/resize_offset_crop_round.jpg)

# Deleting an image.
```bash
curl -XDELETE htp://RIXEL_HOST/images/:id
```
## To disable deleting images:
```ruby
on delete do
  res.status = 403
end
```

## Contributing
Typical github contribution, I'm sure you can figure it out.

## Credits
* [cuba](https://github.com/soveran/cuba)
* [mongoid](https://github.com/mongoid/mongoid)
* [mongoid-paperclip](https://github.com/meskyanichi/mongoid-paperclip)
* [puma](https://github.com/puma/puma)

## License
MIT
