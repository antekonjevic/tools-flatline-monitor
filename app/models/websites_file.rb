# Exports every website's settings as a JSON file, and imports such a file.
#
#   {
#     "flatline": 1,
#     "exported_at": "2026-11-23T09:00:00Z",
#     "websites": [
#       { "name": "Acme shop", "url": "https://shop.example.com", "group": "Acme",
#         "interval_minutes": 5, "required_text": "Add to cart",
#         "failures_before_down": 2, "paused": false }
#     ]
#   }
#
# Importing matches websites by address: matching ones get the file's
# settings, new ones are added, and websites missing from the file are left
# alone. A key left out keeps the current value (or the default for a new
# website). If any entry is invalid, nothing changes.
class WebsitesFile
  VERSION = 1
  MAX_BYTES = 1.megabyte
  MAX_WEBSITES = 1000

  # File key => Check attribute
  FIELDS = {
    "name" => :name,
    "url" => :url,
    "group" => :group_name,
    "interval_minutes" => :interval_minutes,
    "required_text" => :required_phrase,
    "failures_before_down" => :failure_threshold
  }.freeze

  TEXT_FIELDS = %w[name url group required_text].freeze

  Result = Data.define(:added, :updated, :unchanged, :errors) do
    def success? = errors.empty?
    def total = added + updated + unchanged
  end

  def self.export(checks = Check.all)
    websites = checks.sort_by { |check| [ check.group_name ? 0 : 1, check.group_name.to_s.downcase, check.name.downcase ] }
      .map do |check|
        FIELDS.to_h { |key, attribute| [ key, check.public_send(attribute) ] }.merge("paused" => check.paused?)
      end

    JSON.pretty_generate("flatline" => VERSION, "exported_at" => Time.current.utc.iso8601, "websites" => websites) + "\n"
  end

  def self.filename(now = Time.current)
    "flatline-websites-#{now.to_date.iso8601}.json"
  end

  def initialize(content)
    @content = content.to_s
  end

  def import
    entries = parse
    return failure(@errors) if @errors.any?

    plans = entries.each_with_index.map { |entry, index| plan(entry, index) }
    return failure(@errors) if @errors.any?

    counts = Hash.new(0)
    Check.transaction do
      plans.each { |check, paused| counts[apply(check, paused)] += 1 }
    end

    Result.new(added: counts[:added], updated: counts[:updated], unchanged: counts[:unchanged], errors: [])
  end

  private
    def parse
      @errors = []

      if @content.bytesize > MAX_BYTES
        @errors << "The file is too large (the limit is #{MAX_BYTES / 1.megabyte} MB)."
        return []
      end

      data = JSON.parse(@content)
      websites = data.is_a?(Hash) ? data["websites"] : data

      if data.is_a?(Hash) && data["flatline"].is_a?(Integer) && data["flatline"] > VERSION
        @errors << "This file was made by a newer version of Flatline."
      elsif !websites.is_a?(Array)
        @errors << "This doesn't look like a Flatline export: it has no list of websites."
      elsif websites.size > MAX_WEBSITES
        @errors << "The file has more than #{MAX_WEBSITES} websites."
      end

      @errors.any? ? [] : websites
    rescue JSON::ParserError
      @errors << "This isn't a Flatline export: the file isn't valid JSON."
      []
    end

    # Finds or builds the website for one entry and assigns its settings,
    # without saving. Returns [check, paused].
    def plan(entry, index)
      label = "Website #{index + 1}"

      unless entry.is_a?(Hash)
        @errors << "#{label}: should be a set of settings, like the ones in an exported file."
        return
      end

      label = "#{label} (#{entry["name"]})" if entry["name"].is_a?(String) && entry["name"].present?

      if (wrong = TEXT_FIELDS.find { |key| !entry[key].nil? && !entry[key].is_a?(String) })
        @errors << "#{label}: \"#{wrong}\" must be text."
        return
      end

      url = Check.normalize_value_for(:url, entry["url"].to_s)

      if entry["url"].blank?
        @errors << "#{label}: the address (\"url\") is missing."
        return
      elsif (@seen_urls ||= Set.new).add?(url).nil?
        @errors << "#{label}: #{url} appears more than once in the file."
        return
      end

      paused = entry["paused"]
      unless paused.nil? || paused == true || paused == false
        @errors << "#{label}: \"paused\" must be true or false."
        return
      end

      check = Check.where(url: url).order(:id).first ||
        Check.new(interval_minutes: Check::DEFAULT_INTERVAL, failure_threshold: Check::DEFAULT_FAILURE_THRESHOLD)
      FIELDS.each do |key, attribute|
        check.public_send(:"#{attribute}=", entry[key]) if entry.key?(key)
      end

      check.validate
      check.errors.full_messages.each { |message| @errors << "#{label}: #{message}." }

      [ check, paused ]
    end

    def apply(check, paused)
      if check.new_record?
        if paused
          check.paused_at = check.status_changed_at = Time.current
          check.status = "paused"
        end
        check.save!
        return :added
      end

      changed = check.changed?
      check.save!
      check.reschedule_after_edit

      if paused == true && !check.paused?
        check.pause!
        changed = true
      elsif paused == false && check.paused?
        check.resume!
        changed = true
      end

      changed ? :updated : :unchanged
    end

    def failure(errors)
      Result.new(added: 0, updated: 0, unchanged: 0, errors:)
    end
end
