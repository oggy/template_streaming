module TemplateStreaming
  VERSION = [0, 0, 4]

  class << VERSION
    include Comparable

    def to_s
      join('.')
    end
  end
end
