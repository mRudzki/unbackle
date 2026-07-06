require "yaml"
require "erb"

module Unbackle
  DatabaseConfig = Struct.new(
    :environment, :engine, :host, :port, :database, :username, :password, :admin_username, :admin_password,
    keyword_init: true
  )

  module DatabaseConfigLoader
    ENGINE_ALIASES = {
      "postgresql" => :postgres,
      "postgres"   => :postgres,
      "pg"         => :postgres,
      "mysql2"     => :mysql,
      "mysql"      => :mysql,
      "sqlite3"    => :sqlite,
      "sqlite"     => :sqlite,
      "sqlserver"  => :sqlserver,
      "tinytds"    => :sqlserver
    }.freeze

    def self.load(path:, environment:)
      raw = YAML.safe_load(ERB.new(File.read(path)).result, aliases: true)
      env_config = raw.fetch(environment.to_s) do
        raise ArgumentError, "No '#{environment}' section in #{path}"
      end

      adapter = env_config.fetch("adapter") { raise ArgumentError, "Missing 'adapter' key for '#{environment}'" }
      engine = ENGINE_ALIASES.fetch(adapter) { raise ArgumentError, "Unsupported adapter: #{adapter}" }

      DatabaseConfig.new(
        environment: environment.to_s,
        engine: engine,
        host: env_config["host"],
        port: env_config["port"],
        database: env_config.fetch("database") { raise ArgumentError, "Missing 'database' key for '#{environment}'" },
        username: env_config["username"],
        password: env_config["password"],
        admin_username: env_config.fetch("admin_username") { env_config["username"] },
        admin_password: env_config.fetch("admin_password") { env_config["password"] }
      )
    end
  end
end
