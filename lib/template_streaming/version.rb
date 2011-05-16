module TemplateStreaming
  VERSION = [0, 1, 0]

  class << VERSION
    include Comparable

    def to_s
      join('.')
    end
  end
end
