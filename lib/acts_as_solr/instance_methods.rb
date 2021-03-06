module ActsAsSolr #:nodoc:

  module InstanceMethods

    # Solr id is <class.name>:<id> to be unique across all models
    def solr_id
      "#{self.class.name}:#{record_id(self)}"
    end

    # saves to the Solr index
    def solr_save
      return true if indexing_disabled?
      if Helpers.evaluate_condition(configuration[:if], self)
        Helpers.debug "solr_save: #{self.class.name} : #{record_id(self)}"
        solr_add to_solr_doc
        solr_commit if configuration[:auto_commit]
        true
      else
        solr_destroy
      end
    end

    def indexing_disabled?
      Helpers.evaluate_condition(configuration[:offline], self) || !configuration[:if]
    end

    # remove from index
    def solr_destroy
      return true if indexing_disabled?
      Helpers.debug "solr_destroy: #{self.class.name} : #{record_id(self)}"
      solr_delete solr_id
      solr_commit if configuration[:auto_commit]
      true
    end

    # convert instance to Solr document
    def to_solr_doc
      Helpers.debug "to_solr_doc: creating doc for class: #{self.class.name}, id: #{record_id(self)}"
      doc = Solr::Document.new
      doc.boost = Helpers.validate_boost(configuration[:boost], solr_configuration) if configuration[:boost]

      doc << {:id => solr_id,
              solr_configuration[:type_field] => Solr::Util.query_parser_escape(self.class.name),
              solr_configuration[:primary_key_field] => record_id(self).to_s}

      # iterate through the fields and add them to the document,
      configuration[:solr_fields].each do |field_name, options|
        next if [self.class.primary_key, "type"].include?(field_name.to_s)

        field_boost = options[:boost] || solr_configuration[:default_boost]
        field_type = get_solr_field_type(options[:type])
        solr_name = options[:as] || field_name

        value = self.send("#{field_name}_for_solr") rescue nil
        next if value.nil?

        suffix = get_solr_field_type(field_type)
        value = Array(value).map{ |v| ERB::Util.html_escape(v) } # escape each value
        value = value.first if value.size == 1

        field = Solr::Field.new(:name => "#{solr_name}_#{suffix}", :value => value)
        processed_boost = Helpers.validate_boost(field_boost, solr_configuration)
        field.boost = processed_boost
        doc << field
      end

      Helpers.add_dynamic_attributes(doc, configuration)
      Helpers.add_includes(doc, configuration, solr_configuration)
      Helpers.add_tags(doc, configuration)
      Helpers.add_space(doc, configuration)

      Helpers.debug doc.to_json
      doc
    end

    module Helpers
      def self.debug(text)
        logger.debug text rescue nil
      end

      def self.add_space(doc, configuration)
        if configuration[:spatial] and local
          doc << Solr::Field.new(:name => "lat_f", :value => local.latitude)
          doc << Solr::Field.new(:name => "lng_f", :value => local.longitude)
        end
      end

      def self.add_tags(doc, configuration)
        taggings.each do |tagging|
          doc << Solr::Field.new(:name => "tag_facet", :value => tagging.tag.name)
          doc << Solr::Field.new(:name => "tag_t", :value => tagging.tag.name)
        end if configuration[:taggable]
      end

      def self.add_dynamic_attributes(doc, configuration)
        dynamic_attributes.each do |attribute|
          value = ERB::Util.html_escape(attribute.value)
          doc << Solr::Field.new(:name => "#{attribute.name.downcase}_t", :value => value)
          doc << Solr::Field.new(:name => "#{attribute.name.downcase}_facet", :value => value)
        end if configuration[:dynamic_attributes]
      end

      def self.add_includes(doc, configuration, solr_configuration)
        if configuration[:solr_includes].respond_to?(:each)
          configuration[:solr_includes].each do |association, options|
            data = options[:multivalued] ? [] : ""
            field_name = options[:as] || association.to_s.singularize
            field_type = get_solr_field_type(options[:type])
            field_boost = options[:boost] || solr_configuration[:default_boost]
            suffix = get_solr_field_type(field_type)
            case self.class.reflect_on_association(association).macro
            when :has_many, :has_and_belongs_to_many
              records = self.send(association).compact
              unless records.empty?
                records.each {|r| data << include_value(r, options)}
                Array(data).each do |value|
                  field = Solr::Field.new(:name => "#{field_name}_#{suffix}", :value => value)
                  processed_boost = validate_boost(field_boost, solr_configuration)
                  field.boost = processed_boost
                  doc << field
                end
              end
            when :has_one, :belongs_to
              record = self.send(association)
              unless record.nil?
                doc["#{field_name}_#{suffix}"] = include_value(record, options)
              end
            end
          end
        end
      end

      def self.include_value(record, options)
        if options[:using].is_a? Proc
          options[:using].call(record)
        elsif options[:using].is_a? Symbol
          record.send(options[:using])
        else
          if options[:fields]
            fields = {}
            options[:fields].each{ |f| fields[f] = record.send(f) }
          else
            fields = record.attributes
          end
          fields.map{ |k,v| ERB::Util.html_escape(v) }.join(" ")
        end
      end

      def self.validate_boost(boost, solr_configuration)
        boost_value = case boost
        when Float
          return solr_configuration[:default_boost] if boost < 0
          boost
        when Proc
          boost.call(self)
        when Symbol
          if self.respond_to?(boost)
            self.send(boost)
          end
        end

        boost_value || solr_configuration[:default_boost]
      end

      def self.condition_block?(condition)
        condition.respond_to?("call") && (condition.arity == 1 || condition.arity == -1)
      end

      def self.evaluate_condition(condition, field)
        case condition
          when Symbol
            field.send(condition)
          when String
            eval(condition, binding)
          when FalseClass, NilClass
            false
          when TrueClass
            true
          else
            if condition_block?(condition)
              condition.call(field)
            else
              raise(
                ArgumentError,
                "The :#{which_condition} option has to be either a symbol, string (to be eval'ed), proc/method, true/false, or " +
                "class implementing a static validation method"
              )
            end
          end
      end
    end
  end
end
