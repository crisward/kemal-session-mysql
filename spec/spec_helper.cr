require "spec"
require "mysql"
require "../src/kemal-session-mysql"


Db = DB.open "mysql://root@localhost/session_test?max_pool_size=50&initial_pool_size=10&max_idle_pool_size=10&retry_attempts=3"
SESSION_ID = SecureRandom.hex

Spec.before_each do
  Kemal::Session.config.secret = "super-awesome-secret"
  Kemal::Session.config.engine = Kemal::Session::MysqlEngine.new(Db)
end

Spec.after_each do
  Db.exec("DROP TABLE IF EXISTS sessions")
end

def get_from_db(session_id : String)
  Db.query_one "select data from sessions where session_id = ?", session_id, &.read(String)
end

def create_context(session_id : String)
  response = HTTP::Server::Response.new(IO::Memory.new)
  headers = HTTP::Headers.new

  unless session_id == ""
    Kemal::Session.config.engine.create_session(session_id)
    cookies = HTTP::Cookies.new
    cookies << HTTP::Cookie.new(Kemal::Session.config.cookie_name, Kemal::Session.encode(session_id))
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
  include Kemal::Session::StorableObject

  def initialize(@id : Int32, @name : String); end

  def serialize
    self.to_json
  end

  def self.unserialize(value : String)
    UserJsonSerializer.from_json(value)
  end
end

