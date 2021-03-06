class Regulations

  # Downloads metadata about proposed and final regulations from FederalRegister.gov.
  # By default, grabs the last 7 days of both types of regulations.
  #
  # options:
  #   document_number: index a specific document only.
  #
  #   article_type: limit documents to a particular article_type (rule, prorule, notice).
  #     does not apply to public inspection documents.
  #
  #   public_inspection: 
  #     if document_number is not given, fetch all current public inspection documents.
  #     if document_number is given, get the public_inspection version.
  #
  #   year: 
  #     if month is given, is combined with month to index that specific month.
  #     if month is not given, indexes entire year's regulations (12 calls, one per month)
  #   month:
  #     if year is given, is combined with year to index that specific month.
  #     if year is not given, does nothing.
  #
  #   days:
  #     if year is given, does nothing.
  #     if year is not given, fetches last N days of regulations. (Defaults to 7.)
  #
  #   limit: limit processing to N documents
  #
  #   cache: 
  #     cache requests for detail JSON on individual documents
  #     will not cache search requests, is safe to turn on for syncing new documents
  #
  #   skip_text: do not do full text processing (mongo only)
  
  #  Hierarchy of regulatory documents:
  #    All documents:
  #      document_type: "article", "public_inspection"
  #      article_type: "regulation", "notice"
  #
  #    For article_type "regulation":
  #      stage: "proposed", "final"

  def self.run(options = {})
    document_type = options[:public_inspection] ? :public_inspection : :article

    if options[:article_type]
      article_types = [options[:article_type].upcase]
    else
      article_types = ["PRORULE", "RULE", "NOTICE"]
    end

    # single regulation
    if options[:document_number]
      targets = [options[:document_number]]

    # load current day's public inspections
    elsif document_type == :public_inspection
      targets = pi_docs_for options
    
    # proposed and final regulations
    elsif document_type == :article
      targets = []

      article_types.each do |type|
        
        # a whole month or year
        if options[:year]
          year = options[:year].to_i
          months = options[:month] ? [options[:month].to_i] : (1..12).to_a.reverse
          
          months.each do |month|

            # break it up by week
            beginning = Time.parse("#{year}-#{month}-01")

            # 5 weeks, there will be inefficient overlap, oh well
            5.times do |i| 
              ending = (beginning + 6.days) # 7 day window
              targets += regulations_for type, beginning, ending, options
              beginning += 7.days # advance counter by a week
            end
          end

        # default to last 7 days
        else
          days = options[:days] ? options[:days].to_i : 7
          ending = Time.now.midnight # only yyyy-mm-dd is used, time of day doesn't matter
          beginning = ending - days.days
          targets += regulations_for type, beginning, ending, options
        end

      end
    end

    targets = targets.uniq # 5-week window may cause dupes

    if options[:limit]
      targets = targets.first options[:limit].to_i
    end

    count = 0
    search_count = 0

    warnings = []
    missing_links = []
    citation_warnings = []
    batcher = [] # ES batcher

    targets.each do |document_number|

      puts "\n[#{document_type}][#{document_number}] Fetching article..." if options[:debug]
      url = details_url_for document_type, document_number
      destination = destination_for document_type, document_number, "json"

      unless details = Utils.download(url, options.merge(destination: destination, json: true))
        warnings << {message: "Error while polling FR.gov for article details at #{url}, skipping article", url: url}
        next
      end

      rule = Regulation.find_or_initialize_by document_number: document_number

      if !rule.new_record? and (document_type == :public_inspection) and (rule['document_type'] != "public_inspection")
        puts "\tNot storing public inspection, document already released..." if options[:debug]
        next
      end

      if !rule.new_record? and (document_type == :article) and (rule['document_type'] != "article")
        puts "\tArticle replacing public inspection document, wiping fields..." if options[:debug]
        rule.destroy
        rule = Regulation.new document_number: document_number
      end

      
      # common to public inspection documents and to articles
      attributes = {
        document_type: document_type.to_s,

        agency_names: details['agencies'].map {|agency| agency['name'] || agency['raw_name']},
        agency_ids: details['agencies'].map {|agency| agency['id']},
        publication_date: details['publication_date'],

        url: details['html_url'],
        pdf_url: details['pdf_url']
      }

      # maps FR document type to rule stage
      type_to_stage = {
        "Proposed Rule" => "proposed",
        "Rule" => "final"
      }

      if stage = type_to_stage[details['type']]
        attributes[:article_type] = "regulation"
        attributes[:stage] = stage
      
      else # notices
        attributes[:article_type] = details['type'].downcase 
      end


      if document_type == :article
        attributes.merge!(
          title: details['title'],
          docket_ids: details['docket_ids'],
          posted_at: noon_utc_for(details['publication_date']),

          abstract: details['abstract'],
          effective_on: details['effective_on'],
          rins: details['regulation_id_numbers'],
          comments_close_on: details['comments_close_on']
        )

      elsif document_type == :public_inspection
        # The title field can sometimes be blank, in which case it can be cobbled together.
        # According to FR.gov team, this produces the final title 95% of the time.
        # They aren't comfortable with calling it the 'title' - but I think I am.
        title = nil
        if details['title'].present?
          title = details['title']
        elsif details['toc_subject'].present? and details['toc_doc'].present?
          title = [details['toc_subject'], details['toc_doc']].join(" ")
        end

        attributes.merge!(
          title: title,
          docket_ids: details['docket_numbers'],
          posted_at: Utils.utc_parse(details['filed_at'])
        )
      end

      # save the mongo document
      puts "[#{document_number}] Saving to MongoDB..."
      rule.attributes = attributes
      rule.save!
      count += 1

      next if options[:skip_text]
      
      puts "[#{document_number}] Fetching full text..."

      full_text = nil

      if document_type == :article
        # if details['full_text_xml_url']
        #   full_text = text_for :article, document_number, :xml, details['full_text_xml_url'], options
          
        # els
        if details['body_html_url'] 
          full_text = text_for :article, document_number, :html, details['body_html_url'], options

        else
          missing_links << document_number
        end
      else
        if details['raw_text_url']
          full_text = text_for :public_inspection, document_number, :txt, details['raw_text_url'], options
        else
          missing_links << document_number
        end
      end

      unless full_text
        # warning will have been filed
        puts "[#{document_number}] No full text to index, moving on..."
        next
      end


      unless citation_ids = Utils.citations_for(rule, full_text, citation_cache(document_number), options)
        citation_warnings << {message: "Failed to extract citations from #{document_number}"}
        citation_ids = []
      end
      
      # load in the part of the regulation from mongo that gets synced to ES
      fields = {}
      Regulation.basic_fields.each do |field|
        fields[field] = rule[field.to_s]
      end

      # index into elasticsearch
      puts "[#{document_number}] Indexing text of regulation..."
      fields['text'] = full_text
      fields['citation_ids'] = citation_ids

      Utils.es_batch! 'regulations', document_number, fields, batcher, options

      # re-save Mongo record with citation IDs
      rule['citation_ids'] = citation_ids
      rule.save!

      search_count += 1
    end

    # index any leftover docs
    Utils.es_flush! 'regulations', batcher

    
    if warnings.any?
      Report.warning self, "#{warnings.size} warnings", warnings: warnings
    end

    if missing_links.any?
      Report.warning self, "Missing #{missing_links.count} XML and HTML links for full text", missing_links: missing_links
    end

    if citation_warnings.any?
      Report.warning self, "#{citation_warnings.size} warnings while extracting citations", citation_warnings: citation_warnings
    end

    if document_type == :article
      Report.success self, "Processed #{count} #{article_types.join ", "} regulations"
    elsif document_type == :public_inspection
      Report.success self, "Processed #{count} current RULE, PRORULE, and NOTICE public inspection docs"
    end

    Report.success self, "Indexed #{search_count} documents as searchable"
  end


  # document numbers for current PI docs

  def self.pi_docs_for(options)
    base_url = "http://api.federalregister.gov/v1/public-inspection-documents/current.json"
    base_url << "?fields[]=document_number&fields[]=type"

    puts "Fetching current public inspection documents..." if options[:debug]

    unless response = Utils.download(base_url, options.merge(json: true))
      Report.warning self, "Error while polling FR.gov (#{base_url}), aborting for now", url: base_url
      return []
    end

    if response['errors']
      Report.error self, "Errors, not sure what this looks like...", errors: response['errors']
      return []
    end

    unless response['count']
      Report.exception self, "No count field?", response: response.to_s
      return []
    end

    if response['count'] >= 1000
      Report.warning self, "Likely more than 1000 public inspection docs today, that is crazy"
      # continue on
    end

    response['results'].map do |article|
      # the current.json endpoint can't also be filtered by type, so we'll filter client-side
      if ["proposed rule", "rule"].include?(article['type'].downcase)
        article['document_number']
      else
        puts "Skipping non-rule PI doc..." if options[:debug]
        nil
      end
    end.compact
  end


  # document numbers for published regs in the given range

  def self.regulations_for(type, beginning, ending, options)
    base_url = "http://api.federalregister.gov/v1/articles.json"
    base_url << "?conditions[type]=#{type}"
    base_url << "&conditions[publication_date][lte]=#{ending.strftime "%m/%d/%Y"}"
    base_url << "&conditions[publication_date][gte]=#{beginning.strftime "%m/%d/%Y"}"
    base_url << "&fields[]=document_number"
    base_url << "&per_page=1000"

    puts "Fetching #{type} articles from #{beginning.strftime "%m/%d/%Y"} to #{ending.strftime "%m/%d/%Y"}..."
    
    # the API serves a max of 1000 documents, no matter how it's paginated
    # fetch a page of 1000 documents
    # - this should be enough to not miss anything if filtered by month and type, 
    #   but if not, catch it
    # - addendum: NOTICE type articles are more voluminous, and must be filtered per day, or week
    #   2/13/2013 - 3/13/2013, for example: over 2,800 notices. (Wow.)
    
    unless response = Utils.download(base_url, options.merge(json: true))
      Report.warning self, "Error while polling FR.gov (#{base_url}), aborting for now", url: base_url
      return []
    end

    if response['errors']
      Report.exception self, "Errors, not sure what this looks like...", errors: response['errors']
      return []
    end

    unless response['count']
      Report.exception self, "No count field?", response: response.to_s
      return []
    end

    if response['count'] >= 1000
      Report.warning self, "Likely more than 1000 #{type} articles between #{ending} and #{beginning}"
      # continue on
    end

    count = 0

    # not an error, just means there's no results in this timeframe (like for future months)
    unless response['results']
      puts "No results for this time frame" if options[:debug]
      return []
    end

    response['results'].map do |article|
      article['document_number']
    end
  end


  def self.text_for(document_type, document_number, format, url, options)
    destination = destination_for document_type, document_number, format
    
    unless Utils.download(url, options.merge(destination: destination))
      Report.warning self, "Error while polling FR.gov, aborting for now", url: url
      return nil
    end


    body = File.read destination

    if format == :xml
      text = full_text_for Nokogiri::XML(body)
      text_destination = destination_for document_type, document_number, :txt
      Utils.write text_destination, text
      text
    elsif format == :html
      text = full_text_for Nokogiri::HTML(body)
      text_destination = destination_for document_type, document_number, :txt
      Utils.write text_destination, text
      text
    else # text, it's done
      pi_text_for body
    end
  end


  def self.full_text_for(doc)
    return nil unless doc

    strings = (doc/"//*/text()").map do |text| 
      text.inner_text.strip
    end.select {|text| text.present?}

    strings.join " "
  end

  def self.pi_text_for(body)
    body.gsub /[\n\r]/, ' '
  end


  # urls/directories

  def self.details_url_for(document_type, document_number)
    endpoint = {article: "articles", public_inspection: "public-inspection-documents"}[document_type]
    "http://api.federalregister.gov/v1/#{endpoint}/#{document_number}.json"
  end

  def self.destination_for(document_type, document_number, format)
    yearish = document_number.split("-").first
    "data/federalregister/#{yearish}/#{document_number}/#{document_type}.#{format}"
  end

  def self.citation_cache(document_number)
    destination_for "citation", document_number, "json"
  end

  def self.noon_utc_for(timestamp)
    time = Time.zone.parse timestamp
    time.getutc + (12-time.getutc.hour).hours
  end

end