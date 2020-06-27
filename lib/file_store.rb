#require 'pstore'
#require 'pathname'
require 'json'
require 'redis'
require 'time'

class FileStore
  attr_reader :info_hash

  def initialize info_hash
    #@info_hash = info_hash
    @info_hash = info_hash.unpack('H*').first
  end

  # Set or update peer's data
  def set_peer peer_id, data
    #PStore.new(file_path, ultra_safe: true).transaction do |store|
    #  store[:peers] ||= {}
    #  store[:peers][peer_id] = data.merge(expires_at: Time.now + CONF[:announce_interval] * 2)
    #end
    peer_id = peer_id.unpack('H*').first
    redis = Redis.new
    store = redis.hgetall(@info_hash)
    store['peers'] ||= '{}'
    store['peers'] = JSON.parse(store['peers'])
    store['peers'][peer_id] = data.merge('expires_at' => Time.now + CONF[:announce_interval] * 2)
    redis.hset(@info_hash, 'peers', store['peers'].to_json)

    clean_and_denorm!
  end

  # delete given peer
  def delete_peer peer_id
    #PStore.new(file_path, ultra_safe: true).transaction do |store|
    #  (store[:peers] || {}).delete peer_id
    #end
    #clean_and_denorm!
  #rescue PStore::Error
    peer_id = peer_id.unpack('H*').first
    redis = Redis.new
    store = redis.hgetall(@info_hash)
    store['peers'] ||= '{}'
    store['peers'] = JSON.parse(store['peers'])
    store['peers'].delete peer_id
    redis.hset(@info_hash, 'peers', store['peers'].to_json)

    clean_and_denorm!
  end

  # get one peer for a torrent (read only)
  def get_peer peer_id
    #PStore.new(file_path).transaction(true) do |store|
    #  (store[:peers] || {})[peer_id]
    #end
    peer_id = peer_id.unpack('H*').first
    redis = Redis.new
    store = redis.hgetall(@info_hash)
    store['peers'] ||= '{}'
    JSON.parse(store['peers'])[peer_id]
  end

  # get all peers for a torrent (read only)
  def get_peers limit = nil
    #PStore.new(file_path).transaction(true) do |store|
    #  peers = store.fetch(:peers, {})
    #  peers = Hash[peers.to_a[0...limit]] if limit
    #  peers
    #end
    redis = Redis.new
    store = redis.hgetall(@info_hash)
    store['peers'] ||= '{}'
    store['peers'] = JSON.parse(store['peers'])
    peers = (limit ? Hash[store['peers'].to_a[0...limit]] : store['peers'])
    peers
  end

  # Return stat fields
  def get_stats
    #PStore.new(file_path).transaction(true) do |store|
    #  store[:stats] || {}
    #end
    redis = Redis.new
    store = redis.hgetall(@info_hash)
    store['stats'] ||= '{}'
    store['stats'] = JSON.parse(store['stats'])
    store['stats']
  end

  # returns path to the database file
  #def file_path
  #  return @file_path if defined? @file_path
  #  @file_path = Pathname.new("#{CONF[:db_dir]}/#{@info_hash.unpack('H*').first}.pstore")
  #  @file_path.dirname.mkpath
  #  @file_path
  #end

  def self.purge!
    #FileUtils.rm_r CONF[:db_dir], force: true
    redis = Redis.new
    redis.flushdb
  end

  def persisted?
    redis = Redis.new
    redis.keys.include?(@info_hash)
  end

  private

  def clean_and_denorm!
    #count = PStore.new(file_path, ultra_safe: true).transaction do |store|
    #  if peers = store[:peers]
    #    peers.delete_if { |id, peer| peer[:expires_at] < Time.now }
    #    store[:stats] ||= {}
    #    store[:stats][:complete] = peers.count { |_, p| p[:left].to_i == 0 }
    #    store[:stats][:incomplete] = peers.count { |_, p| p[:left].to_i != 0 }
    #    peers.size
    #  else
    #    0
    #  end
    #end
    count = 0
    redis = Redis.new
    store = redis.hgetall(@info_hash)
    if peers = store['peers']
      peers = JSON.parse(peers)
      peers.delete_if { |id, peer| Time.parse(peer['expires_at']) < Time.now }
      store['stats'] ||= '{}'
      store['stats'] = JSON.parse(store['stats'])
      store['stats']['complete'] = peers.count { |_, p| p['left'].to_i == 0 }
      store['stats']['incomplete'] = peers.count { |_, p| p['left'].to_i != 0 }
      redis.hset(@info_hash, 'stats', store['stats'].to_json)
      redis.hset(@info_hash, 'peers', peers.to_json)
      count = peers.size
    else
      count = 0
    end
    #file_path.delete if count == 0
    redis.del(@info_hash) if count == 0
  end
end