require "execjs/runtime"

module ExecJS
  class RubyRacerRuntime < Runtime
    class Context < Runtime::Context
      def initialize(runtime, source = "")
        source = encode(source)

        lock do
          @v8_context = ::V8::Context.new
          @v8_context.eval(source)
        end
      end

      def exec(source, options = {})
        source = encode(source)

        if /\S/ =~ source
          eval "(function(){#{source}})()", options
        end
      end

      def eval(source, options = {})
        source = encode(source)

        if /\S/ =~ source
          lock do
            begin
              unbox @v8_context.eval("(#{source})")
            rescue ::V8::JSError => e
              wrap_error(e)
            end
          end
        end
      end

      def call(properties, *args)
        lock do
          begin
            unbox @v8_context.eval(properties).call(*args)
          rescue ::V8::JSError => e
            wrap_error(e)
          end
        end
      end

      def unbox(value)
        case value
        when ::V8::Function
          nil
        when ::V8::Array
          value.map { |v| unbox(v) }
        when ::V8::Object
          value.inject({}) do |vs, (k, v)|
            vs[k] = unbox(v) unless v.is_a?(::V8::Function)
            vs
          end
        when String
          value.respond_to?(:force_encoding) ?
            value.force_encoding('UTF-8') :
            value
        else
          value
        end
      end

      private
        def lock
          result, exception = nil, nil
          V8::C::Locker() do
            begin
              result = yield
            rescue Exception => e
              exception = e
            end
          end

          if exception
            raise exception
          else
            result
          end
        end

        def wrap_error(e)
          if e.value["name"] == "SyntaxError"
            msg = e.value.to_s
            if e.value.location
              msg << " (Line #{e.value.location.first_line + 1} Column #{e.value.location.first_column + 1})"
            end
            raise RuntimeError, msg
          else
            raise ProgramError, e.value.to_s
          end
        end
    end

    def name
      "therubyracer (V8)"
    end

    def available?
      require "v8"
      true
    rescue LoadError
      false
    end
  end
end
