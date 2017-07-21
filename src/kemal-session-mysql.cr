require "json"
require "kemal-session"

module Kemal
  class Session
    class MysqlEngine < Engine
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
          object: Session::StorableObject::StorableObjectContainer,
        })
      end
      
      @cache : StorageInstance
      @cached_session_id : String
      @cached_session_read_time : Time

      def initialize(@connection : DB::Database, @sessiontable : String = "sessions", @cachetime : Int32 = 5)
        # check if table exists, if not create it
        sql = "CREATE TABLE IF NOT EXISTS #{@sessiontable} (
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
        @cached_session_read_time = Time.utc_now
      end

      def run_gc
        # delete old sessions here
        expiretime = Time.now - Kemal::Session.config.timeout
        sql = "delete from #{@sessiontable} where updated_at < ?"
        @connection.exec(sql, expiretime)
      end

      def all_sessions : Array(StorageInstance)
        array = [] of StorageInstance
        sql = "select data from #{@sessiontable} "
        sessions = @connection.query_all(sql) do |rs|
          json = rs.read(String)
          StorageInstance.from_json(json)
        end
      end

      def create_session(session_id : String)
        session = StorageInstance.new
        data = session.to_json
        sql = "REPLACE into #{@sessiontable} (session_id,data,updated_at) values(?,?,NOW())"
        @connection.exec(sql, session_id, data)
        @cached_session_read_time = Time.utc_now
        return session
      end

      def save_cache()
        data = @cache.to_json
        sql = "update #{@sessiontable} set data=?,updated_at=NOW() where session_id = ? "
        res = @connection.exec(sql, data, @cached_session_id)
      end

      def each_session
        sql = "select data from #{@sessiontable} "
        @connection.query_each(sql) do |rs|
          json = rs.read(String)
          yield StorageInstance.from_json(json)
        end
      end

      def get_session(session_id : String)
        return Session.new(session_id) if session_exists?(session_id)
      end

      def session_exists?(session_id : String) : Bool
        sql = "select id from #{@sessiontable} where session_id = ?"
        begin
          @connection.scalar(sql, session_id)
          return true 
        rescue 
          return false
        end
      end

      def destroy_session(session_id : String)
        sql = "delete from #{@sessiontable} where session_id = ?"
        @connection.exec(sql, session_id)
      end

      def destroy_all_sessions
        @connection.exec("truncate table #{@sessiontable}")
      end

      def load_into_cache(session_id : String) : StorageInstance
        @cached_session_id = session_id
        begin
          json = @connection.query_one "select data from #{@sessiontable} where session_id = ?", session_id, &.read(String)
          @cache = StorageInstance.from_json(json.to_s)
          @cached_session_read_time = Time.utc_now
        rescue ex 
          #recreates session based on id, if it has been deleted?
          create_session(@cached_session_id)
        end
        @connection.exec("update #{@sessiontable} set updated_at = NOW() where session_id = ?",session_id)
        return @cache
      end

      def is_in_cache?(session_id : String) : Bool
        # only read from db once ever 'n' seconds. This should help with a single webpage hitting the db for every asset
        not_too_old = (Time.utc_now.epoch - @cachetime) <= @cached_session_read_time.epoch
        exists = session_id == @cached_session_id
        return exists && not_too_old
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
end
