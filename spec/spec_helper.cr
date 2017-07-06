require "spec"
require "mysql"
require "../src/kemal-session-mysql"

module Kemal
  connection = DB.open "mysql://root@localhost/test?max_pool_size=50&initial_pool_size=10&max_idle_pool_size=10&retry_attempts=3"
  Session.config.secret = "super-awesome-secret"
  Session.config.engine = Session::MysqlEngine.new(connection)

  # REDIS      = Redis.new
  SESSION_ID = SecureRandom.hex

  Spec.before_each do
    # REDIS.flushall
  end

  def create_context(session_id : String)
    response = HTTP::Server::Response.new(IO::Memory.new)
    headers = HTTP::Headers.new

    # I would rather pass nil if no cookie should be created
    # but that throws an error
    unless session_id == ""
      Session.config.engine.create_session(session_id)
      cookies = HTTP::Cookies.new
      cookies << HTTP::Cookie.new(Session.config.cookie_name, Session.encode(session_id))
      cookies.add_request_headers(headers)
    end

    request = HTTP::Request.new("GET", "/", headers)
    return HTTP::Server::Context.new(request, response)
  end

  class UserJsonSerializer
    JSON.mapping({
      id:   Int32,
      name: String,
    })
    include Session::StorableObject

    def initialize(@id : Int32, @name : String); end

    def serialize
      self.to_json
    end

    def self.unserialize(value : String)
      UserJsonSerializer.from_json(value)
    end
  end
end
