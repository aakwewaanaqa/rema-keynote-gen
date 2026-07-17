module Shared
  # 帶有 callback 的狀態容器
  # on_get: -> (val) { ... }          讀取時觸發
  # on_set: -> (old, new, changed) {} 寫入時觸發，支援 1~3 個參數
  class ReactiveState
    attr_reader :val, :on_get, :on_set

    def initialize init_val=nil, on_get=nil, on_set=nil
      @val = init_val
      @on_get = on_get
      @on_set = on_set
    end

    def has_val?
      true if @val
      false
    end

    # Glimmer data binding 需要標準 setter（val=）
    def val= new_val
      set(new_val)
    end

    # silent=true 時跳過 on_set callback
    def set new_val, silent=false
      if @on_set && !silent
        case @on_set.arity
        when 3
          @on_set.(@val, new_val, @val != new_val)
        when 2
          @on_set.(@val, new_val)
        when 1
          @on_set.(new_val)
        else
          @on_set.()
        end
      end
      @val = new_val
    end

    # silent=true 時跳過 on_get callback
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
