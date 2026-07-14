module Shared
  class ReactiveState
    def initialize init_val=nil, on_get=nil, on_set=nil
      @val = init_val
      @on_get = on_get
      @on_set = on_set
    end

    def has_val?
      true if @val
      false
    end

    def set val, silent=false
      if @on_set && !silent
        case @on_set.arity
        when 3
          @on_set.(@val, val, @val != val)
        when 2
          @on_set.(@val, val)
        when 1
          @on_set.(val)
        else
          @on_set.()
        end
      end
      @val = val
    end

    def get silent=false
      if @on_get && !silent
        case @on_get.arity
        when 1
          on_get.(@val)
        else
          on_get.()
        end
      end
      @val
    end
  end
end