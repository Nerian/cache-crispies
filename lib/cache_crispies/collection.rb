# frozen_string_literal: true

module CacheCrispies
  # Handles rendering and possibly caching a collection of models using a
  #   Serializer
  class Collection
    # Initializes a new instance of CacheCrispies::Collection
    #
    # @param colleciton [Object] typically an enumerable containing instances of
    #   ActiveRecord::Base, but could be any enumerable
    # @param serializer [CacheCrispies::Base] a class inheriting from
    #   CacheCrispies::Base
    # @param options [Hash] any optional values from the serializer instance
    def initialize(collection, serializer, options = {})
      @collection = collection
      @serializer = serializer
      @options = options
    end

    # Renders the collection to a JSON-ready Hash trying to cache the hash
    #   along the way
    #
    # @return [Hash] the JSON-ready Hash
    def as_json
      if serializer.do_caching? && collection.respond_to?(:cache_key)
        cached_json
      else
        uncached_json
      end
    end

    private

    attr_reader :collection, :serializer, :options

    def uncached_json
      @serializer.preloads(collection, options)
      collection.map do |model|
        serializer.new(model, options).as_json
      end
    end

    def cached_json
      cache_keys_with_model = collection.each_with_object({}) do |model, hash|
        plan = Plan.new(serializer, model, **options)

        hash[plan.cache_key] = model
      end

      cached_keys_with_values = CacheCrispies.cache.read_multi(*cache_keys_with_model.keys)

      uncached_keys = cache_keys_with_model.keys - cached_keys_with_values.keys
      uncached_models = cache_keys_with_model.fetch_values(*uncached_keys)
      @serializer.preloads(uncached_models, options)

      new_entries = uncached_keys.each_with_object({}) do |key, hash|
        hash[key] = serializer.new(cache_keys_with_model[key], options).as_json
      end

      CacheCrispies.cache.write_multi(new_entries) if new_entries.present?

      results = []
      new_entries_values = new_entries.values

      cache_keys_with_model.keys.each do |key|
        results << (cached_keys_with_values[key] || new_entries_values.shift)
      end

      results
    end
  end
end
