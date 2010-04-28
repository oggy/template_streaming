module TemplateStreaming
  VERSION = [0, 0, 7]

  class << VERSION
    include Comparable

    def to_s
      join('.')
    end
  end
end
