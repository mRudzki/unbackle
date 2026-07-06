require_relative "../lib/unbackle/database_config"
require_relative "../lib/unbackle/auth_function_installer"

namespace :auth do
  desc "Install a DB-native authentication function + BEFORE INSERT/UPDATE/DELETE triggers.\n" \
       "  Usage: rake \"auth:install[users_table,protected_table1:protected_table2,environment]\""
  task :install, [:users_table, :protected_tables, :environment] do |_task, args|
    users_table = args[:users_table] or abort("users_table argument is required")
    protected_tables = (args[:protected_tables] || "").split(":").reject(&:empty?)
    environment = args[:environment] || ENV["UNBACKLE_ENV"] || "development"

    abort("protected_tables argument is required (colon-separated list, e.g. orders:payments)") if protected_tables.empty?

    config_path = File.expand_path("../config/database.yml", __dir__)
    config = Unbackle::DatabaseConfigLoader.load(path: config_path, environment: environment)

    Unbackle::AuthFunctionInstaller.new(config).install(
      table: users_table,
      protected_tables: protected_tables
    )

    puts "Installed unbackle authentication (#{config.engine}) using '#{users_table}', " \
         "protecting: #{protected_tables.join(', ')}"
  end
end
