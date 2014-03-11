require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/array/extract_options'
require 'elasticsearch'

module Waistband
  class Index

    def initialize(index_name, options = {})
      options = options.stringify_keys

      @index_name = index_name
      @stringify = config['stringify']

      # alias subs
      @subs = [options['subs']] if options['subs'].present?
      @subs = @subs.flatten     if @subs.is_a?(Array)
    end

    def exists?
      client.indices.exists index: config_name
    end

    def refresh
      client.indices.refresh index: config_name
    end

    def update_mapping(type)
      client.indices.put_mapping(
        index: config_name,
        type: type,
        body: config['mappings'][type]
      )
    end

    def update_settings
      client.indices.put_settings(
        index: config_name,
        body: settings
      )
    end

    def create
      create!
    rescue ::Waistband::Errors::IndexExists => ex
      true
    end

    def create!
      raise ::Waistband::Errors::IndexExists.new("Index already exists") if exists?
      client.indices.create index: config_name, body: config.except('name', 'stringify')
    end

    def delete
      delete!
    rescue ::Waistband::Errors::IndexNotfound => ex
      true
    end

    def delete!
      raise ::Waistband::Errors::IndexNotfound.new("Index not found") unless exists?
      client.indices.delete index: config_name
    end

    def save(*args)
      body_hash = args.extract_options!
      id = args.first
      type = body_hash.delete(:type) || default_type_name

      # map everything to strings if need be
      body_hash = stringify_all(body_hash) if @stringify

      saved = client.index(
        index: config_name,
        type: type,
        id: id,
        body: body_hash
      )

      saved['_id'].present?
    end

    def read(id, options = {})
      read!(id, options)
    rescue Elasticsearch::Transport::Transport::Errors::NotFound
      nil
    end

    def read!(id, options = {})
      options = options.with_indifferent_access
      type = options[:type] || default_type_name

      client.get(
        index: config_name,
        type: type,
        id: id
      ).with_indifferent_access
    end

    def destroy(id, options = {})
      options = options.with_indifferent_access
      type = options[:type] || default_type_name

      client.delete(
        index: config_name,
        id: id,
        type: type
      )
    end

    def search(body_hash)
      client.search(
        index: config_name,
        body: body_hash
      )
    end

    def alias(alias_name)
      alias_name = full_alias_name alias_name
      client.indices.put_alias(
        index: config_name,
        name: alias_name
      )
    end

    def alias_exists?(alias_name)
      alias_name = full_alias_name alias_name
      client.indices.alias_exists?(
        index: config_name,
        name: alias_name
      )
    end

    def config
      ::Waistband.config.index @index_name
    end

    def client
      @client ||= ::Waistband.config.client
    end

    private

      def full_alias_name(alias_name)
        name = alias_name
        name << "_#{::Waistband.config.env}" unless custom_name?
        name
      end

      def custom_name?
        !!config['name']
      end

      def stringify_all(data)
        data = if data.is_a? Array
          ::Waistband::StringifiedArray.new data
        elsif data.is_a? Hash
          ::Waistband::StringifiedHash.new_from data
        end

        data = data.stringify_all if data.respond_to? :stringify_all
        data
      end

      def default_type_name
        @index_name.singularize
      end

      def settings
        settings = config['settings']['index'].except('number_of_shards')
        {index: settings}
      end

      def config_name
        @subs ? "#{base_config_name}__#{@subs.join('_')}" : base_config_name
      end

      def base_config_name
        return config['name'] if config['name']
        "#{@index_name}_#{::Waistband.config.env}"
      end

    # /private

  end
end
