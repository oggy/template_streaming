module TemplateStreaming
  VERSION = [0, 0, 8]

  class << VERSION
    include Comparable

    def to_s
      join('.')
    end
  end
end
