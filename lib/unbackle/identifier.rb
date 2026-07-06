module Unbackle
  module Identifier
    VALID = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

    def self.validate!(name, kind: "identifier")
      unless name.to_s.match?(VALID)
        raise ArgumentError, "Invalid #{kind}: #{name.inspect}"
      end

      name.to_s
    end
  end
end
