# frozen_string_literal: true

require 'active_record/typed_store/dsl'
require 'active_record/typed_store/behavior'
require 'active_record/typed_store/type'
require 'active_record/typed_store/typed_hash'
require 'active_record/typed_store/identity_coder'

module ActiveRecord::TypedStore
  module Extension
    def typed_store(store_attribute, options={}, &block)
      unless self < Behavior
        include Behavior
        class_attribute :typed_stores, :store_accessors, instance_accessor: false
      end

      dsl = DSL.new(store_attribute, options, &block)
      self.typed_stores = (self.typed_stores || {}).merge(store_attribute => dsl)
      self.store_accessors = typed_stores.each_value.flat_map(&:accessors).map { |a| -a.to_s }.to_set

      typed_klass = TypedHash.create(dsl.fields.values)
      const_set("#{store_attribute}_hash".camelize, typed_klass)

      decorate_attribute_type(store_attribute, :typed_store) do |subtype|
        Type.new(typed_klass, dsl.coder, subtype)
      end

      _store_accessors_module.module_eval do
        dsl.accessors.each do |(accessor_name, prefix_accessor)|
          prefix_accessor ||= accessor_name

          define_method("#{prefix_accessor}=") do |value|
            write_store_attribute(store_attribute, accessor_name, value)
          end

          define_method(prefix_accessor) do
            read_store_attribute(store_attribute, accessor_name)
          end

          define_method("#{prefix_accessor}_changed?") do
            send("#{store_attribute}_changed?") &&
              send(store_attribute)[accessor_name] != send("#{store_attribute}_was")[accessor_name]
          end

          define_method("#{prefix_accessor}_was") do
            send("#{store_attribute}_was")[accessor_name]
          end

          define_method("restore_#{prefix_accessor}!") do
            send("#{prefix_accessor}=", send("#{prefix_accessor}_was"))
          end
        end

        ActiveRecord::Store::ClassMethods.local_stored_attributes ||= {}
        ActiveRecord::Store::ClassMethods.local_stored_attributes[store_attribute] ||= []
        ActiveRecord::Store::ClassMethods.local_stored_attributes[store_attribute] |= keys
      end

      def _store_accessors_module
        @_store_accessors_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end
    end
  end
end
