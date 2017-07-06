require "json"
require "kemal-session"

class Kemal::Session
  class MysqlEngine < Kemal::Session::Engine
    class StorageInstance
        macro define_storage(vars)
          JSON.mapping({
            {% for name, type in vars %}
              {{name.id}}s: Hash(String, {{type}}),
            {% end %}
          })

          {% for name, type in vars %}
            @{{name.id}}s = Hash(String, {{type}}).new
            getter {{name.id}}s

            def {{name.id}}(k : String) : {{type}}
              return @{{name.id}}s[k]
            end

            def {{name.id}}?(k : String) : {{type}}?
              return @{{name.id}}s[k]?
            end

            def {{name.id}}(k : String, v : {{type}})
              @{{name.id}}s[k] = v
            end

            def delete_{{name.id}}(k : String)
              if @{{name.id}}s[k]?
                @{{name.id}}s.delete(k)
              end
            end
          {% end %}

          def initialize
            {% for name, type in vars %}
              @{{name.id}}s = Hash(String, {{type}}).new
            {% end %}
          end
        end

        define_storage({
          int: Int32,
          bigint: Int64,
          string:  String,
          float:   Float64,
          bool: Bool,
          object: Kemal::Session::StorableObject::StorableObjectContainer,
        })
      end

    def initialize(@connection : DB::Database, @sessiontable : String = "sessions")
      # check if table exists, if not create it
      sql = "CREATE TABLE IF NOT EXISTS `?` (
        `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
        `session_id` varchar(32) DEFAULT NULL,
        `data` text,
        `updated_at` datetime DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `session_session_id` (`session_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8; "
      @connection.exec(sql, @sessiontable)
      @cache = StorageInstance.new
      @cached_session_id = ""
    end

    def run_gc
      # delete old sessions here
      #expiretime = Time.now - Kemal::Session.config.timeout.total_seconds
      #sql = "delete from ? where updated_at < ?"
      #@connection.exec(sql, @sessiontable, expiretime)
    end

    def all_sessions : Array(Session)
      array = [] of Session
      sql = "select data from ? "
      sessions = @connection.query_all(sql, @sessiontable)
      sessions.map do |rs|
        json = rs.read(String)
        StorageInstance.from_json(json)
      end
    end

    def create_session(session_id : String)
      session = StorageInstance.new
      data = session.to_json
      sql = "insert into ? (session_id,data) values(?,?)"
      @connection.exec(sql, @sessiontable, session_id, data)
      return session
    end

    def each_session
      sql = "select data from ? "
      @connection.query_each(sql, @sessiontable) do |rs|
        json = rs.read(String)
        yield StorageInstance.from_json(json)
      end
    end

    def get_session(session_id : String)
      rs = @connection.query_one(sql, @sessiontable, session_id)
      json = rs.read(String)
      StorageInstance.from_json(json)
    end

    def destroy_session(session_id : String)
      sql = "delete from ? where session_id = session_id"
      @connection.exec(sql, @sessiontable, expiretime)
    end

    def destroy_all_sessions
      @connection.exec("truncate ?", @sessiontable)
    end

    macro define_delegators(vars)
      {% for name, type in vars %}
        def {{name.id}}(session_id : String, k : String) : {{type}}
          load_into_cache(session_id) unless is_in_cache?(session_id)
          return @cache.{{name.id}}(k)
        end

        def {{name.id}}?(session_id : String, k : String) : {{type}}?
          load_into_cache(session_id) unless is_in_cache?(session_id)
          return @cache.{{name.id}}?(k)
        end

        def {{name.id}}(session_id : String, k : String, v : {{type}})
          load_into_cache(session_id) unless is_in_cache?(session_id)
          @cache.{{name.id}}(k, v)
          save_cache
        end

        def {{name.id}}s(session_id : String) : Hash(String, {{type}})
          load_into_cache(session_id) unless is_in_cache?(session_id)
          return @cache.{{name.id}}s
        end
      {% end %}
    end

    define_delegators({
      int: Int32,
      bigint: Int64,
      string:  String,
      float:   Float64,
      bool: Bool,
      object: Session::StorableObject::StorableObjectContainer,
    })
  end
end
