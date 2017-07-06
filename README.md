# kemal-session-mysql

**THIS DOESN'T WORK, PLEASE DON'T TRY AN USE IT**

Watch this space, once I have it working I'll update this (honest!)

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  kemal-session-mysql:
    github: crystal-lang/crystal-mysql
  mysql:
    github: crisward/kemal-session-mysql
```

## Usage

```crystal
require "kemal"
require "kemal-session-mysql"
require "mysql"

# connect to mysql, update url with your connection info (or perhaps use an ENV var)
connection = DB.open "mysql://root@localhost/test?max_pool_size=50&initial_pool_size=10&max_idle_pool_size=10&retry_attempts=3"

Session.config do |config|
  config.cookie_name = "mysql_test"
  config.secret = "a_secret"
  config.engine = Session::MysqlEngine.new(connection)
  config.timeout = Time::Span.new(1, 0, 0)
end

get "/" do
  puts "Hello World"
end

post "/sign_in" do |context|
  context.session.int("see-it-works", 1)
end

Kemal.run
```


## Contributing

1. Fork it ( https://github.com/crisward/kemal-session-mysql/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [crisward](https://github.com/crisward) Cris Ward - creator, maintainer
