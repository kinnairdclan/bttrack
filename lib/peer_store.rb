require 'json'
require 'redis'
require 'time'
require 'connection_pool'

class PeerStore
  attr_reader :info_hash
  @@connection_pool = ConnectionPool.new(size: CONF[:redis_connections], timeout: CONF[:redis_timeout]) { Redis.new }

  def initialize info_hash
    @info_hash = info_hash.unpack('H*').first
  end

  # Set or update peer's data
  def set_peer peer_id, data
    @@connection_pool.with do |conn|
      peer_id = peer_id.unpack('H*').first
      store = conn.hgetall(@info_hash)
      store['peers'] ||= '{}'
      store['peers'] = JSON.parse(store['peers'])
      store['peers'][peer_id] = data.merge('expires_at' => Time.now + CONF[:announce_interval] * 2)
      conn.hset(@info_hash, 'peers', store['peers'].to_json)
      conn.expire(@info_hash, CONF[:redis_key_expiration])

      clean_and_denorm!(conn)
    end
  end

  # delete given peer
  def delete_peer peer_id
    @@connection_pool.with do |conn|
      peer_id = peer_id.unpack('H*').first
      store = conn.hgetall(@info_hash)
      store['peers'] ||= '{}'
      store['peers'] = JSON.parse(store['peers'])
      store['peers'].delete peer_id
      conn.hset(@info_hash, 'peers', store['peers'].to_json)
      conn.expire(@info_hash, CONF[:redis_key_expiration])

      clean_and_denorm!(conn)
    end
  end

  # get one peer for a torrent (read only)
  def get_peer peer_id
    @@connection_pool.with do |conn|
      peer_id = peer_id.unpack('H*').first
      store = conn.hgetall(@info_hash)
      conn.expire(@info_hash, CONF[:redis_key_expiration])
      store['peers'] ||= '{}'
      JSON.parse(store['peers'])[peer_id]
    end
  end

  # get all peers for a torrent (read only)
  def get_peers limit = nil
    @@connection_pool.with do |conn|
      store = conn.hgetall(@info_hash)
      conn.expire(@info_hash, CONF[:redis_key_expiration])
      store['peers'] ||= '{}'
      store['peers'] = JSON.parse(store['peers'])
      peers = (limit ? Hash[store['peers'].to_a[0...limit]] : store['peers'])
      peers
    end
  end

  # Return stat fields
  def get_stats
    @@connection_pool.with do |conn|
      store = conn.hgetall(@info_hash)
      conn.expire(@info_hash, CONF[:redis_key_expiration])
      store['stats'] ||= '{}'
      store['stats'] = JSON.parse(store['stats'])
      store['stats']
    end
  end

  def persisted?
    @@connection_pool.with do |conn|
      conn.keys.include?(@info_hash)
    end
  end

  def self.all
    @@connection_pool.with do |conn|
      conn.keys.each do |key|
        yield [key].pack('H*')
      end
    end
  end

  def self.purge!
    @@connection_pool.with do |conn|
      conn.flushdb
    end
  end

  private

  def clean_and_denorm!(exist_conn)
    count = 0
    store = exist_conn.hgetall(@info_hash)
    if peers = store['peers']
      peers = JSON.parse(peers)
      peers.delete_if { |id, peer| Time.parse(peer['expires_at']) < Time.now }
      store['stats'] ||= '{}'
      store['stats'] = JSON.parse(store['stats'])
      store['stats']['complete'] = peers.count { |_, p| p['left'].to_i == 0 }
      store['stats']['incomplete'] = peers.count { |_, p| p['left'].to_i != 0 }
      exist_conn.hset(@info_hash, 'stats', store['stats'].to_json)
      exist_conn.hset(@info_hash, 'peers', peers.to_json)
      exist_conn.expire(@info_hash, CONF[:redis_key_expiration])
      count = peers.size
    else
      count = 0
    end
    exist_conn.del(@info_hash) if count == 0
  end
end