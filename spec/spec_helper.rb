ENV['RACK_ENV'] = 'test'
require 'rack/test'
require 'fileutils'
require './bttrack'

module RSpecMixin
  include Rack::Test::Methods
  def app() Sinatra::Application end
end

# For RSpec 2.x
RSpec.configure do |c|
  c.include RSpecMixin

  c.before(:each) { PeerStore.purge! }
  c.after(:suite) { PeerStore.purge! }
end
