module NoBrainer::Document::Index
  extend ActiveSupport::Concern

  included do
    class_attribute :indexes
    self.indexes = {}
  end

  module ClassMethods
    def index(name, *args)
      name = name.to_sym
      options = args.extract_options!
      raise "Too many arguments: #{args}" if args.size > 1

      kind, what = case args.first
        when nil   then [:single,   name.to_sym]
        when Array then [:compound, args.first.map(&:to_sym)]
        when Proc  then [:proc,     args.first]
        else raise "Index argument must be a lambda or a list of fields"
      end

      # FIXME Primary key may not always be :id
      if name.in? NoBrainer::Criteria::Chainable::Where::RESERVED_FIELDS || name == :id
        raise "Cannot use a reserved field name: #{name}"
      end
      if has_field?(name) && kind != :single
        raise "Cannot reuse field name #{name}"
      end

      indexes[name] = {:kind => kind, :what => what, :options => options}
    end

    def remove_index(name)
      indexes.delete(name.to_sym)
    end

    def has_index?(name)
      !!indexes[name.to_sym]
    end

    def field(name, options={})
      name = name.to_sym

      if has_index?(name) && indexes[name][:kind] != :single
        raise "Cannot reuse index name #{name}"
      end

      super
      index(name, options[:index].is_a?(Hash) ? options[:index] : {}) if options[:index]
    end

    def belongs_to(target, options={})
      super.tap do |relation|
        index relation.foreign_key if options[:index]
      end
    end

    def remove_field(name)
      remove_index(name) if fields[name.to_sym][:index]
      super
    end

    def perform_create_index(index_name, options={})
      index_name = index_name.to_sym
      index_args = self.indexes[index_name]

      index_proc = case index_args[:kind]
        when :single   then nil
        when :compound then ->(doc) { index_args[:what].map { |field| doc[field] } }
        when :proc     then index_args[:what]
      end

      NoBrainer.run { self.table.index_create(index_name, index_args[:options], &index_proc) }
      NoBrainer.run { self.table.index_wait(index_name) } if options[:wait]
      STDERR.puts "Created index #{self}.#{index_name}" if options[:verbose]
    end

    def perform_drop_index(index_name, options={})
      NoBrainer.run { self.table.index_drop(index_name) }
      STDERR.puts "Dropped index #{self}.#{index_name}" if options[:verbose]
    end

    def perform_update_indexes(options={})
      current_indexes = NoBrainer.run { self.table.index_list }.map(&:to_sym)

      (current_indexes - self.indexes.keys).each do |index_name|
        perform_drop_index(index_name, options)
      end

      (self.indexes.keys - current_indexes).each do |index_name|
        perform_create_index(index_name, options)
      end
    end
    alias_method :update_indexes, :perform_update_indexes
  end
end
