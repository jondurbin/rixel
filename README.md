# rixel
Rixel - ruby web-server for on-the-fly image resizing, shaping, cropping and face recognition.

# ${1:Rixel}
Rixel is a ruby web-server which servers as an image proxy that can transform images on-the-fly based on URL parameters.  Rixel supports local disk storage as well as AWS S3.  When using S3, rixel uses LRU disk caching, with configurable values for maximum cache files, total cache size, or max age of the file.

## Installation
### Dependencies
1.) ruby-2.2.2 (hint: rvm is awesome)
2.) mongodb
3.) Bundler (gem install bundler)
### Install
1.) Clone or fork this project.
2.) Update the mongoid configuration (config/mongoid.yml)
3.) Update the rixel configuration (config/rixel.yml)
4.) Install gems used by pixel with bundler: bundle
5.) *To support face recognition (coming soon) and automatic face cropping, you must install opencv 2.4.11 (opencv 3.* doesn't play nicely with the ruby-opencv gem in my experience).

## Running the server
bundle exec puma -e ENVIRONMENT -p PORT, for example:
bundle exec puma -e production -p 80

## Contributing
Typical github contribution, I'm sure you can figure it out.

## Credits
cuba - https://github.com/soveran/cuba
mongoid - https://github.com/mongoid/mongoid
mongoid-paperclip - https://github.com/meskyanichi/mongoid-paperclip
puma - https://github.com/puma/puma

## License
MIT
