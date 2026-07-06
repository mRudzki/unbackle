require_relative "auth_functions/postgres_generator"
require_relative "auth_functions/mysql_generator"

module Unbackle
  class AuthFunctionInstaller
    def initialize(config)
      @config = config
    end

    def install(table:, protected_tables:, username_column: "username", password_column: "password_digest")
      generator = build_generator(table: table, username_column: username_column, password_column: password_column)
      connection = connect

      begin
        run(connection, generator.function_statements)
        protected_tables.each do |protected_table|
          run(connection, generator.trigger_statements(protected_table))
        end
      ensure
        connection.close
      end
    end

    private

    def build_generator(table:, username_column:, password_column:)
      klass = case @config.engine
              when :postgres then AuthFunctions::PostgresGenerator
              when :mysql then AuthFunctions::MysqlGenerator
              else
                raise ArgumentError, "Unsupported engine for auth function install: #{@config.engine}"
              end

      klass.new(
        table: table,
        username_column: username_column,
        password_column: password_column,
        admin_username: @config.admin_username
      )
    end

    # Installing functions/extensions/triggers is a DDL operation, so it runs
    # as the admin (highest) DB user, not the restricted application user
    # that database.yml's username/password describe.
    def connect
      case @config.engine
      when :postgres
        require "pg"
        PG.connect(
          host: @config.host,
          port: @config.port,
          dbname: @config.database,
          user: @config.admin_username,
          password: @config.admin_password
        )
      when :mysql
        require "mysql2"
        Mysql2::Client.new(
          host: @config.host,
          port: @config.port,
          database: @config.database,
          username: @config.admin_username,
          password: @config.admin_password
        )
      else
        raise ArgumentError, "Unsupported engine: #{@config.engine}"
      end
    end

    def run(connection, statements)
      statements.each do |statement|
        case @config.engine
        when :postgres then connection.exec(statement)
        when :mysql then connection.query(statement)
        end
      end
    end
  end
end
