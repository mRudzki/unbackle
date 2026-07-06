require_relative "../identifier"

module Unbackle
  module AuthFunctions
    # Assumes `password_column` already holds a crypt()-compatible digest
    # (e.g. a bcrypt hash produced by Rails' has_secure_password).
    class PostgresGenerator
      def initialize(table:, admin_username:, username_column: "username", password_column: "password_digest")
        @table = Identifier.validate!(table, kind: "table")
        @username_column = Identifier.validate!(username_column, kind: "column")
        @password_column = Identifier.validate!(password_column, kind: "column")
        @admin_username = admin_username.to_s
      end

      def function_statements
        [
          "CREATE EXTENSION IF NOT EXISTS pgcrypto;",
          authenticate_function_sql,
          session_credentials_function_sql,
          trigger_function_sql
        ]
      end

      def trigger_statements(protected_table)
        protected_table = Identifier.validate!(protected_table, kind: "table")
        [
          "DROP TRIGGER IF EXISTS unbackle_auth_before_write ON #{protected_table};",
          <<~SQL
            CREATE TRIGGER unbackle_auth_before_write
            BEFORE INSERT OR UPDATE OR DELETE ON #{protected_table}
            FOR EACH ROW EXECUTE FUNCTION unbackle_require_authentication();
          SQL
        ]
      end

      private

      def authenticate_function_sql
        <<~SQL
          CREATE OR REPLACE FUNCTION unbackle_authenticate_user(p_username text, p_password text)
          RETURNS boolean AS $$
          DECLARE
            v_digest text;
          BEGIN
            SELECT #{@password_column} INTO v_digest
            FROM #{@table}
            WHERE #{@username_column} = p_username;

            IF v_digest IS NULL THEN
              RETURN false;
            END IF;

            RETURN crypt(p_password, v_digest) = v_digest;
          END;
          $$ LANGUAGE plpgsql SECURITY DEFINER;
        SQL
      end

      def session_credentials_function_sql
        <<~SQL
          CREATE OR REPLACE FUNCTION unbackle_set_session_credentials(p_username text, p_password text)
          RETURNS void AS $$
          BEGIN
            PERFORM set_config('unbackle.username', p_username, false);
            PERFORM set_config('unbackle.password', p_password, false);
          END;
          $$ LANGUAGE plpgsql;
        SQL
      end

      def trigger_function_sql
        <<~SQL
          CREATE OR REPLACE FUNCTION unbackle_require_authentication()
          RETURNS trigger AS $$
          DECLARE
            v_username text := current_setting('unbackle.username', true);
            v_password text := current_setting('unbackle.password', true);
          BEGIN
            IF session_user <> #{quote(@admin_username)} THEN
              IF v_username IS NULL OR NOT unbackle_authenticate_user(v_username, v_password) THEN
                RAISE EXCEPTION 'unbackle: authentication required before modifying %', TG_TABLE_NAME;
              END IF;
            END IF;

            IF TG_OP = 'DELETE' THEN
              RETURN OLD;
            END IF;
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;
        SQL
      end

      def quote(value)
        "'#{value.gsub("'", "''")}'"
      end
    end
  end
end
