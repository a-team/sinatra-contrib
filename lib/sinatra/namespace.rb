require 'backports'
require 'sinatra/base'
require 'sinatra/decompile'

module Sinatra
  module Namespace
    def self.new(base, pattern, conditions = {}, &block)
      Module.new do
        extend NamespacedMethods
        include InstanceMethods
        @base, @extensions    = base, []
        @pattern, @conditions = compile(pattern, conditions)
        @templates            = Hash.new { |h,k| @base.templates[k] }
        namespace = self
        before { extend(@namespace = namespace) }
        class_eval(&block)
      end
    end

    module InstanceMethods
      def settings
        @namespace
      end

      def template_cache
        super.fetch(:nested, @namespace) { Tilt::Cache.new }
      end

      def error_block!(*keys)
        if block = keys.inject(nil) { |b,k| b ||= @namespace.errors[k] }
          instance_eval(&block)
        else
          super
        end
      end
    end

    module SharedMethods
      def namespace(pattern, conditions = {}, &block)
        Sinatra::Namespace.new(self, pattern, conditions, &block)
      end
    end

    module NamespacedMethods
      include SharedMethods
      include Sinatra::Decompile
      attr_reader :base, :templates

      def self.prefixed(*names)
        names.each { |n| define_method(n) { |*a, &b| prefixed(n, *a, &b) }}
      end

      prefixed :before, :after, :delete, :get, :head, :options, :patch, :post, :put

      def helpers(*extensions, &block)
        class_eval(&block) if block_given?
        include(*extensions) if extensions.any?
      end

      def register(*extensions, &block)
        extensions << Module.new(&block) if block_given?
        @extensions += extensions
        extensions.each do |extension|
          extend extension
          extension.registered(self) if extension.respond_to?(:registered)
        end
      end

      def invoke_hook(name, *args)
        @extensions.each { |e| e.send(name, *args) if e.respond_to?(name) }
      end

      def errors
        @errors ||= {}
      end

      def not_found(&block)
        error(404, &block)
      end

      def error(codes = Exception, &block)
        [*codes].each { |c| errors[c] = block }
      end

      def respond_to(*args)
        return @conditions[:provides] || base.respond_to if args.empty?
        @conditions[:provides] = args
      end

      def set(key, value = self, &block)
        raise ArgumentError, "may not set #{key}" if key != :views
        return key.each { |k,v| set(k, v) } if block.nil? and value == self
        block ||= proc { value }
        singleton_class.send(:define_method, key, &block)
      end

      def enable(*opts)
        opts.each { |key| set(key, true) }
      end

      def disable(*opts)
        opts.each { |key| set(key, false) }
      end

      def template(name, &block)
        filename, line = caller_locations.first
        templates[name] = [block, filename, line.to_i]
      end

      def layout(name=:layout, &block)
        template name, &block
      end

      private

      def app
        base.respond_to?(:base) ? base.base : base
      end

      def compile(pattern, conditions, default_pattern = nil)
        if pattern.respond_to? :to_hash
          conditions = conditions.merge pattern.to_hash
          pattern = nil
        end
        base_pattern, base_conditions = @pattern, @conditions
        pattern         ||= default_pattern
        base_pattern    ||= base.pattern    if base.respond_to? :pattern
        base_conditions ||= base.conditions if base.respond_to? :conditions
        [ prefixed_path(base_pattern, pattern),
          (base_conditions || {}).merge(conditions) ]
      end

      def prefixed_path(a, b)
        return a || b || // unless a and b
        a, b = decompile(a), decompile(b) unless a.class == b.class
        a, b = regexpify(a), regexpify(b) unless a.class == b.class
        path = a.class.new "#{a}#{b}"
        path = /^#{path}$/ if path.is_a? Regexp and base == app
        path
      end

      def regexpify(pattern)
        pattern = Sinatra::Base.send(:compile, pattern).first.inspect
        pattern.gsub! /^\/(\^|\\A)?|(\$|\\Z)?\/$/, ''
        Regexp.new pattern
      end

      def prefixed(method, pattern = nil, conditions = {}, &block)
        default = '*' if method == :before or method == :after
        pattern, conditions = compile pattern, conditions, default
        result = base.send(method, pattern, conditions, &block)
        invoke_hook :route_added, method.to_s.upcase, pattern, block
        result
      end

      def method_missing(meth, *args, &block)
        base.send(meth, *args, &block)
      end
    end

    module BaseMethods
      include SharedMethods
    end

    def self.extend_object(base)
      base.extend BaseMethods
    end
  end

  register Sinatra::Namespace
  Delegator.delegate :namespace
end
