require_relative "../identifier"

module Unbackle
  module AuthFunctions
    # NOTE: MySQL has no native bcrypt/crypt() verification. This generator
    # assumes `password_column` holds SHA2-256 hex digests. If your users
    # table stores bcrypt hashes (e.g. Rails has_secure_password), verifying
    # them in pure MySQL SQL requires a UDF plugin - out of scope here.
    class MysqlGenerator
      EVENTS = %w[INSERT UPDATE DELETE].freeze

      def initialize(table:, admin_username:, username_column: "username", password_column: "password_digest")
        @table = Identifier.validate!(table, kind: "table")
        @username_column = Identifier.validate!(username_column, kind: "column")
        @password_column = Identifier.validate!(password_column, kind: "column")
        @admin_username = admin_username.to_s
      end

      def function_statements
        [
          "DROP FUNCTION IF EXISTS unbackle_authenticate_user;",
          authenticate_function_sql
        ]
      end

      def trigger_statements(protected_table)
        protected_table = Identifier.validate!(protected_table, kind: "table")
        EVENTS.flat_map do |event|
          trigger_name = "unbackle_auth_before_#{event.downcase}_#{protected_table}"
          [
            "DROP TRIGGER IF EXISTS #{trigger_name};",
            <<~SQL
              CREATE TRIGGER #{trigger_name}
              BEFORE #{event} ON #{protected_table}
              FOR EACH ROW
              BEGIN
                IF SUBSTRING_INDEX(USER(), '@', 1) <> #{quote(@admin_username)} THEN
                  IF @unbackle_username IS NULL OR NOT unbackle_authenticate_user(@unbackle_username, @unbackle_password) THEN
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'unbackle: authentication required';
                  END IF;
                END IF;
              END
            SQL
          ]
        end
      end

      private

      def authenticate_function_sql
        <<~SQL
          CREATE FUNCTION unbackle_authenticate_user(p_username VARCHAR(255), p_password VARCHAR(255))
          RETURNS BOOLEAN
          DETERMINISTIC
          READS SQL DATA
          BEGIN
            DECLARE v_digest VARCHAR(255);
            SELECT #{@password_column} INTO v_digest FROM #{@table} WHERE #{@username_column} = p_username LIMIT 1;
            IF v_digest IS NULL THEN
              RETURN FALSE;
            END IF;
            RETURN SHA2(p_password, 256) = v_digest;
          END
        SQL
      end

      def quote(value)
        "'#{value.gsub("'", "''")}'"
      end
    end
  end
end
